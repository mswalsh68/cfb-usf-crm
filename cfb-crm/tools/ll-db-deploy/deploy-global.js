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
const ok   = (s) => `${C.green}✔${C.reset} ${s}`;
const skip = (s) => `${C.yellow}–${C.reset} ${C.dim}${s}${C.reset}`;
const fail = (s) => `${C.red}✘${C.reset} ${C.red}${s}${C.reset}`;
const info = (s) => `${C.cyan}ℹ${C.reset} ${s}`;
const head = (s) => `\n${C.bold}${C.white}${s}${C.reset}`;
const rule = ()  => `${C.gray}${'─'.repeat(60)}${C.reset}`;

// ─── CLI flags ────────────────────────────────────────────────────────────────
const argv          = process.argv.slice(2);
const FLAG_SPS_ONLY = argv.includes('--sps-only');
const FLAG_STATUS   = argv.includes('--status');
const FLAG_DRY_RUN  = argv.includes('--dry-run');
const FLAG_BASELINE = argv.includes('--baseline');
const FLAG_FORCE    = argv.includes('--force');
const FLAG_ENV      = envName; // 'dev' or 'prod'

if (argv.includes('--help') || argv.includes('-h')) {
  console.log(`
${C.bold}deploy-global.js${C.reset} — LegacyLink GlobalDB deployment tool

${C.bold}Usage:${C.reset}
  node deploy-global.js                     Deploy migrations + SPs to dev GlobalDB
  node deploy-global.js --env prod          Deploy migrations + SPs to prod GlobalDB
  node deploy-global.js --sps-only          Re-apply stored procedures only (dev)
  node deploy-global.js --env prod --sps-only  Re-apply stored procedures only (prod)
  node deploy-global.js --status            Show migration status (dev)
  node deploy-global.js --env prod --status Show migration status (prod)
  node deploy-global.js --dry-run           Preview what would run (dev)
  node deploy-global.js --baseline          Stamp pending migrations as applied (dev)

${C.bold}npm scripts:${C.reset}
  npm run deploy:global         → dev  deploy
  npm run deploy:global:prod    → prod deploy
  npm run deploy:global:sps     → dev  --sps-only
  npm run deploy:global:sps:prod→ prod --sps-only
  npm run status:global         → dev  --status
  npm run status:global:prod    → prod --status
`);
  process.exit(0);
}

// ─── Paths ────────────────────────────────────────────────────────────────────
const REPO_DATABASES_PATH = process.env.REPO_DATABASES_PATH
  ? path.resolve(process.env.REPO_DATABASES_PATH)
  : path.resolve(__dirname, '..', '..', 'databases'); // tool lives at cfb-crm/tools/ll-db-deploy

const MIGRATIONS_DIR = path.join(REPO_DATABASES_PATH, 'global', 'migrations');
const SPS_DIR        = path.join(REPO_DATABASES_PATH, 'global', 'stored-procedures');

// All global SP files, applied in this order
const SP_FILES = [
  'sp_Global_AllProcedures.sql',
  'sp_TeamConfig.sql',
  'sp_Teams.sql',
];

// Validate paths up-front
if (!fs.existsSync(MIGRATIONS_DIR)) {
  console.error(fail(`Migrations directory not found: ${MIGRATIONS_DIR}`));
  console.error(info('Set REPO_DATABASES_PATH in .env to point at the cfb-crm/databases folder.'));
  process.exit(1);
}
if (!fs.existsSync(SPS_DIR)) {
  console.error(fail(`Stored-procedures directory not found: ${SPS_DIR}`));
  process.exit(1);
}
for (const spFile of SP_FILES) {
  const fp = path.join(SPS_DIR, spFile);
  if (!fs.existsSync(fp)) {
    console.error(fail(`SP file not found: ${fp}`));
    process.exit(1);
  }
}

// ─── GlobalDB name ─────────────────────────────────────────────────────────────
// Dev:  GLOBAL_DB_NAME or fallback to DevLegacyLinkGlobal
// Prod: GLOBAL_DB_NAME_PROD or fallback to LegacyLinkGlobal
const globalDbName = FLAG_ENV === 'prod'
  ? (process.env.GLOBAL_DB_NAME_PROD || 'LegacyLinkGlobal')
  : (process.env.GLOBAL_DB_NAME      || 'DevLegacyLinkGlobal');

// ─── SQL Server config helpers ────────────────────────────────────────────────
const serverName = process.env.DB_SERVER    || 'localhost\\SQLEXPRESS';
const trustCert  = (process.env.DB_TRUST_CERT ?? 'true') !== 'false';
const encrypt    = (process.env.DB_ENCRYPT  ?? 'false') !== 'false';

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
function splitBatches(sqlText) {
  return sqlText
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

  // Add applied_by if missing (schema drift guard)
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
}

async function getAppliedMigrations(pool) {
  const result = await pool.request()
    .query(`SELECT migration_name FROM dbo.migration_history ORDER BY migration_name`);
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
    .sort()
    .map(f => ({ name: f, filePath: path.join(MIGRATIONS_DIR, f) }));
}

// ─── Status mode ──────────────────────────────────────────────────────────────
async function showStatus(pool) {
  const migrations = getMigrationFiles();
  console.log(info(`Migration files in repo: ${migrations.length}`));
  console.log(head(`📊 ${globalDbName}`));
  console.log(rule());

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
}

// ─── Deploy ───────────────────────────────────────────────────────────────────
async function deploy(pool) {
  const errors = [];

  // ── Ensure migration_history table exists ──────────────────────────────────
  await ensureHistoryTable(pool);
  console.log(ok('migration_history table ready'));

  if (!FLAG_SPS_ONLY) {
    // ── Run migrations ─────────────────────────────────────────────────────────
    const files   = getMigrationFiles();
    const applied = await getAppliedMigrations(pool);

    console.log(info(`Found ${files.length} migration file(s), ${applied.size} already applied`));

    for (const { name, filePath } of files) {
      if (applied.has(name)) {
        console.log(skip(`[migration] ${name}`));
        continue;
      }

      if (FLAG_BASELINE) {
        if (!FLAG_DRY_RUN) await recordMigration(pool, name);
        console.log(`${C.cyan}⊕${C.reset} [baseline] ${name}`);
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
        break; // stop further migrations after first failure
      }
    }
  }

  // ── Apply stored procedures ────────────────────────────────────────────────
  if (FLAG_BASELINE) {
    console.log(skip('[stored-procs] skipped in baseline mode'));
    return errors;
  }

  if (errors.length === 0) {
    for (const spFile of SP_FILES) {
      const spPath = path.join(SPS_DIR, spFile);
      if (FLAG_DRY_RUN) {
        console.log(`${C.yellow}(dry-run)${C.reset} Would apply: ${spFile}`);
        continue;
      }
      try {
        const spSql = fs.readFileSync(spPath, 'utf8');
        await runBatches(pool, spSql, spFile);
        console.log(ok(`[stored-procs] ${spFile}`));
      } catch (err) {
        console.log(fail(`[stored-procs] ${spFile}\n           ${err.message}`));
        errors.push(err.message);
      }
    }
  } else {
    console.log(skip('[stored-procs] skipped due to migration error'));
  }

  return errors;
}

// ─── Main ─────────────────────────────────────────────────────────────────────
// ─── Pre-flight sync check ────────────────────────────────────────────────────
// Before a prod deploy, verify dev GlobalDB has no migrations that prod is
// missing. Aborts unless --force is passed.
async function preflightSyncCheck(devDb, prodDb) {
  console.log(info(`Pre-flight: checking ${devDb} → ${prodDb} migration sync...`));
  let devPool, prodPool;
  try {
    devPool  = await connectTo(devDb);
    prodPool = await connectTo(prodDb);

    const getMigrations = async (pool, db) => {
      try {
        const r = await pool.request().query(
          `SELECT migration_name FROM dbo.migration_history ORDER BY migration_name`
        );
        return new Set(r.recordset.map(row => row.migration_name.replace(/\.sql$/i, '')));
      } catch {
        return new Set(); // migration_history doesn't exist yet
      }
    };

    const devMigs  = await getMigrations(devPool,  devDb);
    const prodMigs = await getMigrations(prodPool, prodDb);
    const missing  = [...devMigs].filter(m => !prodMigs.has(m));

    if (missing.length === 0) {
      console.log(ok(`Migration sync OK — ${devDb} and ${prodDb} are in sync\n`));
      return;
    }

    console.log(`\n${C.red}${C.bold}⚠  PRE-FLIGHT FAILED — prod is behind dev:${C.reset}`);
    missing.forEach(m => console.log(`   ${C.yellow}–${C.reset} ${m} applied in ${devDb} but NOT in ${prodDb}`));
    console.log(`\n${C.yellow}Fix: copy the missing migration(s) to cfb-usf-crm-prod and re-run.${C.reset}`);
    console.log(`${C.yellow}Override with --force if you intentionally want to skip this check.${C.reset}\n`);
    process.exit(1);

  } finally {
    if (devPool)  await devPool.close().catch(() => {});
    if (prodPool) await prodPool.close().catch(() => {});
  }
}

async function main() {
  const envLabel = FLAG_ENV === 'prod'
    ? `${C.red}${C.bold}PRODUCTION${C.reset}`
    : `${C.green}dev${C.reset}`;

  console.log(`\n${C.bold}${C.cyan}╔══════════════════════════════════╗${C.reset}`);
  console.log(`${C.bold}${C.cyan}║   ll-db-deploy  GlobalDB         ║${C.reset}`);
  console.log(`${C.bold}${C.cyan}╚══════════════════════════════════╝${C.reset}`);
  console.log(`${C.cyan}ℹ${C.reset} Environment : ${envLabel}  (${envFile})`);
  console.log(`${C.cyan}ℹ${C.reset} Target DB   : ${C.bold}${globalDbName}${C.reset}  on ${serverName}`);
  if (FLAG_DRY_RUN) console.log(`${C.yellow}⚠  DRY RUN — no changes will be made${C.reset}`);

  // Pre-flight: when deploying to prod, verify dev isn't ahead
  if (FLAG_ENV === 'prod' && !FLAG_STATUS && !FLAG_FORCE) {
    const devGlobalDb = process.env.GLOBAL_DB_NAME || 'DevLegacyLinkGlobal';
    await preflightSyncCheck(devGlobalDb, globalDbName);
  }

  let pool;
  try {
    pool = await connectTo(globalDbName);
  } catch (err) {
    console.error(fail(`Cannot connect to ${globalDbName}: ${err.message}`));
    process.exit(1);
  }

  try {
    if (FLAG_STATUS) {
      await showStatus(pool);
      console.log('\n' + rule());
      console.log(info('Status check complete.\n'));
      return;
    }

    console.log(head(`▶ ${globalDbName}`));
    console.log(rule());

    const errors = await deploy(pool);

    console.log(head('═══ Summary ═══'));
    console.log(rule());
    if (errors.length === 0) {
      console.log(ok(globalDbName));
      console.log(`\n${C.green}${C.bold}GlobalDB deployment succeeded.${C.reset}\n`);
    } else {
      console.log(fail(globalDbName));
      console.log(`\n${C.red}${C.bold}GlobalDB deployment failed. See errors above.${C.reset}\n`);
      process.exit(1);
    }
  } finally {
    await pool.close();
  }
}

main().catch(err => {
  console.error(fail(`Unexpected error: ${err.message}`));
  console.error(err.stack);
  process.exit(1);
});
