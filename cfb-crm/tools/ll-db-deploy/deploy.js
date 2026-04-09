#!/usr/bin/env node
'use strict';

// Load env file: --env prod → .env.production, default → .env
const envIndex = process.argv.indexOf('--env');
const envName  = envIndex !== -1 ? process.argv[envIndex + 1] : 'dev';
const envFile  = envName === 'prod' ? '.env.production' : '.env';
require('dotenv').config({ path: require('path').resolve(__dirname, envFile) });

const fs   = require('fs');
const path = require('path');
const sql  = require('mssql');

// ─── ANSI colours ────────────────────────────────────────────────────────────
const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  dim:    '\x1b[2m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
  white:  '\x1b[37m',
  gray:   '\x1b[90m',
};
const ok    = (s) => `${C.green}✔${C.reset} ${s}`;
const skip  = (s) => `${C.yellow}–${C.reset} ${C.dim}${s}${C.reset}`;
const fail  = (s) => `${C.red}✘${C.reset} ${C.red}${s}${C.reset}`;
const info  = (s) => `${C.cyan}ℹ${C.reset} ${s}`;
const head  = (s) => `\n${C.bold}${C.white}${s}${C.reset}`;
const rule  = ()  => `${C.gray}${'─'.repeat(60)}${C.reset}`;

// ─── CLI flags ────────────────────────────────────────────────────────────────
const argv          = process.argv.slice(2);
const FLAG_ALL      = argv.includes('--all');
const FLAG_SPS_ONLY = argv.includes('--sps-only');
const FLAG_STATUS   = argv.includes('--status');
const FLAG_DRY_RUN  = argv.includes('--dry-run');
const FLAG_BASELINE = argv.includes('--baseline');
const FLAG_FORCE    = argv.includes('--force');
const FLAG_ENV      = envName; // 'dev' or 'prod'
const dbIndex       = argv.indexOf('--db');
const FLAG_DB       = dbIndex !== -1 ? argv[dbIndex + 1] : null;

// Migrations that are one-off historical scripts not safe to re-run on
// consolidated-schema DBs. They are auto-skipped (marked applied) unless
// the DB is brand-new and has never had any migrations applied.
const SKIP_ON_EXISTING = new Set([
  '002_migrate_data.sql', // Migrates data from old CfbRoster/CfbAlumni — not applicable to new schema
]);

if (!FLAG_ALL && !FLAG_DB && !FLAG_STATUS && !FLAG_BASELINE) {
  console.log(`
${C.bold}ll-db-deploy${C.reset} — LegacyLink AppDB deployment tool

${C.bold}Usage:${C.reset}
  node deploy.js --db <DbName>              Deploy to a single AppDB (dev env)
  node deploy.js --all                      Deploy to ALL dev AppDBs
  node deploy.js --env prod --all           Deploy to ALL prod AppDBs
  node deploy.js --all --sps-only           Re-apply stored procedures only
  node deploy.js --status                   Show migration status (dev)
  node deploy.js --env prod --status        Show migration status (prod)
  node deploy.js --all --baseline           Stamp pending migrations without running
  node deploy.js --dry-run --env prod --all Preview prod deploy without executing

${C.bold}npm scripts:${C.reset}
  npm run deploy:dev        → dev  --db DevLegacyLinkApp
  npm run deploy:all        → dev  --all
  npm run deploy:sps        → dev  --all --sps-only
  npm run status            → dev  --status
  npm run deploy:prod       → prod --all
  npm run deploy:prod:sps   → prod --all --sps-only
  npm run status:prod       → prod --status
`);
  process.exit(0);
}

// ─── Paths ────────────────────────────────────────────────────────────────────
const REPO_DATABASES_PATH = process.env.REPO_DATABASES_PATH
  ? path.resolve(process.env.REPO_DATABASES_PATH)
  : path.resolve(__dirname, '..', '..', 'databases'); // tool lives at cfb-crm/tools/ll-db-deploy

const MIGRATIONS_DIR = path.join(REPO_DATABASES_PATH, 'app', 'migrations');
const SPS_FILE       = path.join(REPO_DATABASES_PATH, 'app', 'stored-procedures', 'sp_App_AllProcedures.sql');

// Validate paths up-front
if (!fs.existsSync(MIGRATIONS_DIR)) {
  console.error(fail(`Migrations directory not found: ${MIGRATIONS_DIR}`));
  console.error(info('Set REPO_DATABASES_PATH in .env to point at the cfb-crm/databases folder.'));
  process.exit(1);
}
if (!fs.existsSync(SPS_FILE)) {
  console.error(fail(`SP file not found: ${SPS_FILE}`));
  process.exit(1);
}

// ─── SQL Server config helpers ────────────────────────────────────────────────
const serverName = process.env.DB_SERVER || 'localhost\\SQLEXPRESS';
const trustCert  = (process.env.DB_TRUST_CERT ?? 'true') !== 'false';
const encrypt    = (process.env.DB_ENCRYPT ?? 'false') !== 'false';

function makePool(database) {
  return new sql.ConnectionPool({
    server: serverName,
    database,
    options: { encrypt, trustServerCertificate: trustCert },
    authentication: {
      type: 'default',
      options: {
        userName: process.env.DB_USER ?? '',
        password: process.env.DB_PASS ?? '',
      },
    },
    connectionTimeout: 15000,
    requestTimeout:    60000,
  });
}

async function connectTo(database) {
  const pool = makePool(database);
  await pool.connect();
  return pool;
}

// ─── SQL batch execution ───────────────────────────────────────────────────────
// Split on lines that are exactly "GO" (case-insensitive, optional whitespace)
function splitBatches(sql) {
  return sql
    .split(/^\s*GO\s*$/im)
    .map(b => b.trim())
    .filter(b => b.length > 0);
}

async function runBatches(pool, sqlText, label) {
  const batches = splitBatches(sqlText);
  for (let i = 0; i < batches.length; i++) {
    try {
      await pool.request().query(batches[i]);
    } catch (err) {
      throw new Error(`Batch ${i + 1}/${batches.length} of [${label}] failed:\n  ${err.message}`);
    }
  }
}

// ─── migration_history table ──────────────────────────────────────────────────
async function ensureHistoryTable(pool) {
  // 1. Create table if it doesn't exist at all
  await pool.request().query(`
    IF NOT EXISTS (
      SELECT 1 FROM sys.tables t
      JOIN sys.schemas s ON t.schema_id = s.schema_id
      WHERE s.name = 'dbo' AND t.name = 'migration_history'
    )
    BEGIN
      CREATE TABLE dbo.migration_history (
        id             INT           IDENTITY(1,1) PRIMARY KEY,
        migration_name NVARCHAR(260) NOT NULL UNIQUE,
        applied_at     DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        applied_by     NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
      );
    END
  `);

  // 2. Handle old schema: rename 'migration_id' → 'migration_name' if needed
  //    (older AppDBs created before ll-db-deploy used migration_id)
  const colCheck = await pool.request().query(`
    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo'
      AND TABLE_NAME   = 'migration_history'
      AND COLUMN_NAME  = 'migration_id'
  `);
  const alreadyRenamed = await pool.request().query(`
    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = 'dbo'
      AND TABLE_NAME   = 'migration_history'
      AND COLUMN_NAME  = 'migration_name'
  `);
  if (colCheck.recordset.length > 0 && alreadyRenamed.recordset.length === 0) {
    // Drop the unique constraint on the old column first (constraint name varies)
    await pool.request().query(`
      DECLARE @con NVARCHAR(200);
      SELECT @con = kc.name
      FROM   sys.key_constraints kc
      JOIN   sys.index_columns   ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
      JOIN   sys.columns          c ON c.object_id  = ic.object_id AND c.column_id = ic.column_id
      JOIN   sys.tables           t ON t.object_id  = kc.parent_object_id
      JOIN   sys.schemas          s ON s.schema_id  = t.schema_id
      WHERE  s.name = 'dbo' AND t.name = 'migration_history' AND c.name = 'migration_id'
        AND  kc.type = 'UQ';
      IF @con IS NOT NULL
        EXEC('ALTER TABLE dbo.migration_history DROP CONSTRAINT [' + @con + ']');
    `);
    // Rename the column
    await pool.request().query(`
      EXEC sp_rename 'dbo.migration_history.migration_id', 'migration_name', 'COLUMN';
    `);
    // Re-add the unique constraint
    await pool.request().query(`
      IF NOT EXISTS (
        SELECT 1 FROM sys.indexes i
        JOIN sys.tables t ON t.object_id = i.object_id
        JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE s.name = 'dbo' AND t.name = 'migration_history'
          AND i.is_unique = 1 AND i.is_primary_key = 0
      )
      BEGIN
        ALTER TABLE dbo.migration_history
          ADD CONSTRAINT uq_migration_history_name UNIQUE (migration_name);
      END
    `);
    console.log(ok('Migrated migration_history: renamed migration_id → migration_name'));
  }

  // 3. Add applied_by column if missing (old schema didn't have it)
  await pool.request().query(`
    IF NOT EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'migration_history'
        AND COLUMN_NAME = 'applied_by'
    )
    BEGIN
      ALTER TABLE dbo.migration_history
        ADD applied_by NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER;
    END
  `);

  // 4. If a 'checksum' column exists and is NOT NULL, make it nullable
  //    (older schema had checksum NOT NULL but we don't compute checksums)
  await pool.request().query(`
    IF EXISTS (
      SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
      WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'migration_history'
        AND COLUMN_NAME = 'checksum' AND IS_NULLABLE = 'NO'
    )
    BEGIN
      ALTER TABLE dbo.migration_history
        ALTER COLUMN checksum NVARCHAR(64) NULL;
    END
  `);
}

async function getAppliedMigrations(pool) {
  const result = await pool.request()
    .query(`SELECT migration_name FROM dbo.migration_history ORDER BY migration_name`);
  // Normalise: some old entries may lack the .sql extension — accept both forms
  return new Set(
    result.recordset.map(r => {
      const n = r.migration_name;
      return n.toLowerCase().endsWith('.sql') ? n : n + '.sql';
    })
  );
}

async function recordMigration(pool, name) {
  await pool.request()
    .input('name', sql.NVarChar(260), name)
    .query(`INSERT INTO dbo.migration_history (migration_name) VALUES (@name)`);
}

// ─── Get migration files ───────────────────────────────────────────────────────
function getMigrationFiles() {
  return fs.readdirSync(MIGRATIONS_DIR)
    .filter(f => f.match(/^\d+.*\.sql$/i))
    .sort()  // lexicographic — 001_ < 002_ < ... < 009_ works as long as zero-padded
    .map(f => ({ name: f, filePath: path.join(MIGRATIONS_DIR, f) }));
}

// ─── Connect to GlobalDB and get target AppDBs ────────────────────────────────
async function getTargetDbs() {
  const globalDbName = process.env.DB_NAME || 'LegacyLinkGlobal';
  console.log(info(`Connecting to ${serverName}/${globalDbName} to read team registry…`));

  let globalPool;
  try {
    globalPool = await connectTo(globalDbName);
  } catch (err) {
    throw new Error(`Cannot connect to ${globalDbName}: ${err.message}`);
  }

  try {
    const result = await globalPool.request().query(`
      SELECT name, abbr, ISNULL(app_db, '') AS app_db
      FROM dbo.teams
      WHERE ISNULL(app_db, '') <> ''
      ORDER BY name
    `);
    return result.recordset; // [{ name, abbr, app_db }]
  } finally {
    await globalPool.close();
  }
}

// ─── Deploy to a single AppDB ─────────────────────────────────────────────────
async function deployToDb(team) {
  const label = `${team.name} (${team.abbr}) → ${team.app_db}`;
  console.log(head(`▶ ${label}`));
  console.log(rule());

  let pool;
  try {
    pool = await connectTo(team.app_db);
  } catch (err) {
    console.log(fail(`Cannot connect to ${team.app_db}: ${err.message}`));
    return { db: team.app_db, success: false };
  }

  const errors = [];

  try {
    // ── Ensure migration_history table exists ──────────────────────────────
    await ensureHistoryTable(pool);
    console.log(ok('migration_history table ready'));

    if (!FLAG_SPS_ONLY) {
      // ── Run migrations ───────────────────────────────────────────────────
      const files   = getMigrationFiles();
      const applied = await getAppliedMigrations(pool);
      const isExistingDb = applied.size > 0; // DB has prior migration history

      console.log(info(`Found ${files.length} migration file(s), ${applied.size} already applied`));

      for (const { name, filePath } of files) {
        if (applied.has(name)) {
          console.log(skip(`[migration] ${name}`));
          continue;
        }

        // --baseline: stamp as applied without running
        if (FLAG_BASELINE) {
          if (!FLAG_DRY_RUN) await recordMigration(pool, name);
          console.log(`${C.cyan}⊕${C.reset} [baseline] ${name}`);
          continue;
        }

        // Skip legacy one-off migrations on DBs that already have some history
        // (those DBs were set up with the new consolidated schema)
        if (isExistingDb && SKIP_ON_EXISTING.has(name)) {
          if (!FLAG_DRY_RUN) await recordMigration(pool, name);
          console.log(skip(`[migration] ${name}  (one-off historical — auto-skipped)`));
          continue;
        }

        if (FLAG_DRY_RUN) {
          console.log(`${C.yellow}(dry-run)${C.reset} Would apply: ${name}`);
          continue;
        }
        try {
          const sqlText = fs.readFileSync(filePath, 'utf8');
          await runBatches(pool, sqlText, name);
          await recordMigration(pool, name);
          console.log(ok(`[migration] ${name}`));
        } catch (err) {
          console.log(fail(`[migration] ${name}\n           ${err.message}`));
          errors.push(err.message);
          // Stop running further migrations on this DB after a failure
          break;
        }
      }
    }

    // ── Apply stored procedures ─────────────────────────────────────────────
    // Skip SPs during --baseline (point is only to stamp history, not run SQL)
    if (FLAG_BASELINE) {
      console.log(skip('[stored-procs] skipped in baseline mode — run deploy after to apply SPs'));
      return { db: team.app_db, success: true };
    }

    if (errors.length === 0) {
      if (FLAG_DRY_RUN) {
        console.log(`${C.yellow}(dry-run)${C.reset} Would apply: sp_App_AllProcedures.sql`);
      } else {
        try {
          const spSql = fs.readFileSync(SPS_FILE, 'utf8');
          await runBatches(pool, spSql, 'sp_App_AllProcedures.sql');
          console.log(ok('[stored-procs] sp_App_AllProcedures.sql'));
        } catch (err) {
          console.log(fail(`[stored-procs] ${err.message}`));
          errors.push(err.message);
        }
      }
    } else {
      console.log(skip('[stored-procs] skipped due to migration error'));
    }

  } finally {
    await pool.close();
  }

  return { db: team.app_db, success: errors.length === 0 };
}

// ─── Status mode ──────────────────────────────────────────────────────────────
async function showStatus(teams) {
  const migrations = getMigrationFiles();
  console.log(info(`Migration files in repo: ${migrations.length}`));

  for (const team of teams) {
    const label = `${team.name} (${team.abbr}) → ${team.app_db}`;
    console.log(head(`📊 ${label}`));
    console.log(rule());

    let pool;
    try {
      pool = await connectTo(team.app_db);
    } catch (err) {
      console.log(fail(`Cannot connect: ${err.message}`));
      continue;
    }

    try {
      await ensureHistoryTable(pool);
      const applied = await getAppliedMigrations(pool);

      for (const { name } of migrations) {
        if (applied.has(name)) {
          console.log(ok(name));
        } else {
          console.log(`${C.yellow}○${C.reset} ${name}  ${C.yellow}(pending)${C.reset}`);
        }
      }
      console.log(info(`${applied.size}/${migrations.length} migrations applied`));
    } finally {
      await pool.close();
    }
  }
}

// ─── Pre-flight sync check ────────────────────────────────────────────────────
// Before a prod deploy, verify DevLegacyLinkApp has no migrations that the
// target prod AppDB is missing. Aborts unless --force is passed.
async function preflightSyncCheck(devDb, prodDb) {
  console.log(info(`Pre-flight: checking ${devDb} → ${prodDb} migration sync...`));
  let devPool, prodPool;
  try {
    devPool  = await connectTo(devDb);
    try {
      prodPool = await connectTo(prodDb);
    } catch {
      console.log(`${C.yellow}⚠  ${prodDb} does not exist yet — skipping pre-flight for this DB${C.reset}\n`);
      return;
    }

    const getMigrations = async (pool) => {
      try {
        const r = await pool.request().query(
          `SELECT migration_name FROM dbo.migration_history ORDER BY migration_name`
        );
        return new Set(r.recordset.map(row => row.migration_name.replace(/\.sql$/i, '')));
      } catch {
        return new Set();
      }
    };

    const devMigs = await getMigrations(devPool);
    const prodMigs = await getMigrations(prodPool);
    const missing  = [...devMigs].filter(m => !prodMigs.has(m));

    if (missing.length === 0) {
      console.log(ok(`Migration sync OK — ${devDb} and ${prodDb} are in sync\n`));
      return;
    }

    console.log(`\n${C.red}${C.bold}⚠  PRE-FLIGHT FAILED — ${prodDb} is behind ${devDb}:${C.reset}`);
    missing.forEach(m => console.log(`   ${C.yellow}–${C.reset} ${m} applied in ${devDb} but NOT in ${prodDb}`));
    console.log(`\n${C.yellow}Fix: copy the missing migration(s) to cfb-usf-crm-prod and re-run.${C.reset}`);
    console.log(`${C.yellow}Override with --force if you intentionally want to skip this check.${C.reset}\n`);
    process.exit(1);

  } finally {
    if (devPool)  await devPool.close().catch(() => {});
    if (prodPool) await prodPool.close().catch(() => {});
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const envLabel = FLAG_ENV === 'prod'
    ? `${C.red}${C.bold}PRODUCTION${C.reset}`
    : `${C.green}dev${C.reset}`;
  console.log(`\n${C.bold}${C.cyan}╔══════════════════════════════════╗${C.reset}`);
  console.log(`${C.bold}${C.cyan}║   ll-db-deploy  v1.0             ║${C.reset}`);
  console.log(`${C.bold}${C.cyan}╚══════════════════════════════════╝${C.reset}`);
  console.log(`${C.cyan}ℹ${C.reset} Environment: ${envLabel}  (${envFile})`);
  if (FLAG_DRY_RUN) console.log(`${C.yellow}⚠  DRY RUN — no changes will be made${C.reset}`);

  // Pre-flight: when deploying to prod, verify DevLegacyLinkApp isn't ahead
  // of each prod AppDB. Checks each target DB individually.
  if (FLAG_ENV === 'prod' && !FLAG_STATUS && !FLAG_FORCE) {
    const devAppDb = 'DevLegacyLinkApp';
    // Get prod targets from GlobalDB first, then check each one
    let prodTeams;
    try {
      prodTeams = await getTargetDbs();
    } catch (err) {
      console.error(fail(`Pre-flight: cannot read teams from GlobalDB: ${err.message}`));
      process.exit(1);
    }
    const targets = FLAG_DB
      ? prodTeams.filter(t => t.app_db.toLowerCase() === FLAG_DB.toLowerCase())
      : prodTeams;

    for (const team of targets) {
      if (team.app_db === devAppDb) continue; // skip dev db if it somehow appears
      await preflightSyncCheck(devAppDb, team.app_db);
    }
  }

  let allTeams;
  try {
    allTeams = await getTargetDbs();
  } catch (err) {
    console.error(fail(err.message));
    process.exit(1);
  }

  if (allTeams.length === 0) {
    console.log(fail('No teams with app_db found in LegacyLinkGlobal.teams — nothing to do.'));
    process.exit(1);
  }

  // Filter to requested targets
  let targets;
  if (FLAG_DB) {
    targets = allTeams.filter(t => t.app_db.toLowerCase() === FLAG_DB.toLowerCase());
    if (targets.length === 0) {
      // Allow specifying a db name that's not yet in the teams table (e.g. dev db)
      console.log(info(`No team found with app_db='${FLAG_DB}' — targeting it directly.`));
      targets = [{ name: FLAG_DB, abbr: '?', app_db: FLAG_DB }];
    }
  } else {
    // --all or --status
    targets = allTeams;
  }

  console.log(info(`Targeting ${targets.length} database(s): ${targets.map(t => t.app_db).join(', ')}\n`));

  // ── Status mode ─────────────────────────────────────────────────────────────
  if (FLAG_STATUS) {
    await showStatus(targets);
    console.log('\n' + rule());
    console.log(info('Status check complete.\n'));
    return;
  }

  // ── Deploy mode ──────────────────────────────────────────────────────────────
  const results = [];
  for (const team of targets) {
    const result = await deployToDb(team);
    results.push(result);
  }

  // ── Summary ──────────────────────────────────────────────────────────────────
  console.log(head('═══ Summary ═══'));
  console.log(rule());
  let allOk = true;
  for (const { db, success } of results) {
    if (success) {
      console.log(ok(db));
    } else {
      console.log(fail(db));
      allOk = false;
    }
  }
  console.log(rule());
  if (allOk) {
    console.log(`\n${C.green}${C.bold}All deployments succeeded.${C.reset}\n`);
  } else {
    console.log(`\n${C.red}${C.bold}One or more deployments failed. See errors above.${C.reset}\n`);
    process.exit(1);
  }
}

main().catch(err => {
  console.error(fail(`Unexpected error: ${err.message}`));
  console.error(err.stack);
  process.exit(1);
});
