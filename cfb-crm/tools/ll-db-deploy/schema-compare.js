#!/usr/bin/env node
'use strict';

// Load env file: --env prod → .env.production, default → .env
const envIndex = process.argv.indexOf('--env');
const envName  = envIndex !== -1 ? process.argv[envIndex + 1] : 'dev';
const envFile  = envName === 'prod' ? '.env.production' : '.env';
require('dotenv').config({ path: require('path').resolve(__dirname, envFile) });

const sql = require('mssql');

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
  magenta:'\x1b[35m',
};
const ok      = (s) => `  ${C.green}✔${C.reset} ${s}`;
const missing = (s) => `  ${C.red}✘${C.reset} ${C.red}${s}${C.reset}`;
const extra   = (s) => `  ${C.yellow}+${C.reset} ${C.yellow}${s}${C.reset}`;
const diff    = (s) => `  ${C.magenta}≠${C.reset} ${C.magenta}${s}${C.reset}`;
const info    = (s) => `${C.cyan}ℹ${C.reset} ${s}`;
const head    = (s) => `\n${C.bold}${C.white}${s}${C.reset}`;
const rule    = ()  => `${C.gray}${'─'.repeat(60)}${C.reset}`;
const section = (s) => `\n${C.bold}${C.cyan}  ── ${s}${C.reset}`;

// ─── SQL Server config ────────────────────────────────────────────────────────
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
  try {
    await pool.connect();
    return pool;
  } catch (err) {
    throw new Error(`Cannot connect to [${database}]: ${err.message}`);
  }
}

// ─── Schema query helpers ────────────────────────────────────────────────────

// Returns Map<tableName, Set<"colName:DATA_TYPE(len)"> >
async function getTables(pool) {
  const result = await pool.request().query(`
    SELECT
      t.TABLE_NAME,
      c.COLUMN_NAME,
      c.DATA_TYPE,
      CASE
        WHEN c.CHARACTER_MAXIMUM_LENGTH IS NOT NULL THEN
          c.DATA_TYPE + '(' +
            CASE WHEN c.CHARACTER_MAXIMUM_LENGTH = -1 THEN 'MAX'
                 ELSE CAST(c.CHARACTER_MAXIMUM_LENGTH AS NVARCHAR)
            END + ')'
        WHEN c.NUMERIC_PRECISION IS NOT NULL AND c.DATA_TYPE NOT IN ('int','bigint','smallint','tinyint','bit')
          THEN c.DATA_TYPE + '(' + CAST(c.NUMERIC_PRECISION AS NVARCHAR) + ',' + CAST(c.NUMERIC_SCALE AS NVARCHAR) + ')'
        ELSE c.DATA_TYPE
      END AS type_desc,
      c.IS_NULLABLE,
      c.COLUMN_DEFAULT,
      c.ORDINAL_POSITION
    FROM INFORMATION_SCHEMA.TABLES t
    JOIN INFORMATION_SCHEMA.COLUMNS c
      ON c.TABLE_SCHEMA = t.TABLE_SCHEMA AND c.TABLE_NAME = t.TABLE_NAME
    WHERE t.TABLE_SCHEMA = 'dbo'
      AND t.TABLE_TYPE   = 'BASE TABLE'
      AND t.TABLE_NAME  != 'migration_history'
    ORDER BY t.TABLE_NAME, c.ORDINAL_POSITION
  `);

  const tables = new Map();
  for (const row of result.recordset) {
    if (!tables.has(row.TABLE_NAME)) tables.set(row.TABLE_NAME, new Map());
    tables.get(row.TABLE_NAME).set(row.COLUMN_NAME, {
      type:     row.type_desc,
      nullable: row.IS_NULLABLE,
      default:  row.COLUMN_DEFAULT,
      ordinal:  row.ORDINAL_POSITION,
    });
  }
  return tables;
}

// Returns Map<procName, definition_hash>
async function getStoredProcs(pool) {
  const result = await pool.request().query(`
    SELECT
      p.name AS proc_name,
      LEN(m.definition) AS def_len
    FROM sys.procedures p
    JOIN sys.sql_modules m ON m.object_id = p.object_id
    WHERE SCHEMA_NAME(p.schema_id) = 'dbo'
    ORDER BY p.name
  `);
  const procs = new Map();
  for (const row of result.recordset) {
    procs.set(row.proc_name, row.def_len);
  }
  return procs;
}

// Returns migration names applied — normalized to bare name without .sql extension
// so that old records (stored without .sql) and new records (stored with .sql) compare equal.
async function getMigrations(pool) {
  try {
    const result = await pool.request().query(`
      SELECT migration_name FROM dbo.migration_history ORDER BY migration_name
    `);
    return new Set(
      result.recordset.map(r => {
        const n = r.migration_name;
        return n.toLowerCase().endsWith('.sql') ? n.slice(0, -4) : n;
      })
    );
  } catch {
    return null; // table doesn't exist
  }
}

// ─── Compare logic ────────────────────────────────────────────────────────────

function compareTables(srcTables, tgtTables, srcLabel, tgtLabel) {
  let issues = 0;

  const srcNames = new Set(srcTables.keys());
  const tgtNames = new Set(tgtTables.keys());

  // Tables in src but not in tgt
  for (const t of srcNames) {
    if (!tgtNames.has(t)) {
      console.log(missing(`Table [${t}] exists in ${srcLabel} but MISSING in ${tgtLabel}`));
      issues++;
    }
  }

  // Tables in tgt but not in src
  for (const t of tgtNames) {
    if (!srcNames.has(t)) {
      console.log(extra(`Table [${t}] exists in ${tgtLabel} but NOT in ${srcLabel}`));
      issues++;
    }
  }

  // Tables in both — compare columns
  for (const t of srcNames) {
    if (!tgtNames.has(t)) continue;
    const srcCols = srcTables.get(t);
    const tgtCols = tgtTables.get(t);

    let tablePrinted = false;
    const printTable = () => {
      if (!tablePrinted) {
        console.log(`\n  ${C.bold}[${t}]${C.reset}`);
        tablePrinted = true;
      }
    };

    // Columns in src but not in tgt
    for (const [col] of srcCols) {
      if (!tgtCols.has(col)) {
        printTable();
        console.log(missing(`  Column [${col}] in ${srcLabel} but MISSING in ${tgtLabel}`));
        issues++;
      }
    }

    // Columns in tgt but not in src
    for (const [col] of tgtCols) {
      if (!srcCols.has(col)) {
        printTable();
        console.log(extra(`  Column [${col}] in ${tgtLabel} but NOT in ${srcLabel}`));
        issues++;
      }
    }

    // Type / nullability differences
    for (const [col, srcMeta] of srcCols) {
      if (!tgtCols.has(col)) continue;
      const tgtMeta = tgtCols.get(col);
      if (srcMeta.type !== tgtMeta.type) {
        printTable();
        console.log(diff(`  Column [${col}]: type ${srcLabel}=${srcMeta.type}  ${tgtLabel}=${tgtMeta.type}`));
        issues++;
      }
      if (srcMeta.nullable !== tgtMeta.nullable) {
        printTable();
        console.log(diff(`  Column [${col}]: nullable ${srcLabel}=${srcMeta.nullable}  ${tgtLabel}=${tgtMeta.nullable}`));
        issues++;
      }
    }

    if (tablePrinted) issues++; // already counted per-issue above; this is just cosmetic
  }

  return issues;
}

function compareProcs(srcProcs, tgtProcs, srcLabel, tgtLabel) {
  let issues = 0;

  for (const [name] of srcProcs) {
    if (!tgtProcs.has(name)) {
      console.log(missing(`Proc [${name}] in ${srcLabel} but MISSING in ${tgtLabel}`));
      issues++;
    }
  }

  for (const [name] of tgtProcs) {
    if (!srcProcs.has(name)) {
      console.log(extra(`Proc [${name}] in ${tgtLabel} but NOT in ${srcLabel}`));
      issues++;
    }
  }

  // Note definition length differences (not exact match — just flag obvious drift)
  for (const [name, srcLen] of srcProcs) {
    if (!tgtProcs.has(name)) continue;
    const tgtLen = tgtProcs.get(name);
    if (Math.abs(srcLen - tgtLen) > 10) { // ignore tiny whitespace diffs
      console.log(diff(`Proc [${name}]: def length differs (${srcLabel}=${srcLen}  ${tgtLabel}=${tgtLen})`));
      issues++;
    }
  }

  return issues;
}

// ─── Run one comparison ───────────────────────────────────────────────────────

async function compare(srcDb, tgtDb) {
  console.log(head(`▶ Compare: ${C.green}${srcDb}${C.reset}  →  ${C.yellow}${tgtDb}${C.reset}`));
  console.log(rule());
  console.log(info(`Source (reference): ${srcDb}`));
  console.log(info(`Target (production): ${tgtDb}`));

  let srcPool, tgtPool;
  try {
    process.stdout.write(`  Connecting to ${srcDb}…`);
    srcPool = await connectTo(srcDb);
    console.log(' ' + C.green + 'OK' + C.reset);
  } catch (err) {
    console.log(' ' + C.red + 'FAILED' + C.reset);
    console.log(`  ${err.message}`);
    return { srcDb, tgtDb, connected: false };
  }

  try {
    process.stdout.write(`  Connecting to ${tgtDb}…`);
    tgtPool = await connectTo(tgtDb);
    console.log(' ' + C.green + 'OK' + C.reset);
  } catch (err) {
    console.log(' ' + C.red + 'FAILED' + C.reset);
    console.log(`  ${err.message}`);
    await srcPool.close();
    return { srcDb, tgtDb, connected: false };
  }

  let totalIssues = 0;

  try {
    // ── Tables & Columns ──────────────────────────────────────────────────────
    console.log(section('Tables & Columns'));
    const [srcTables, tgtTables] = await Promise.all([
      getTables(srcPool),
      getTables(tgtPool),
    ]);
    console.log(info(`  ${srcDb}: ${srcTables.size} tables    ${tgtDb}: ${tgtTables.size} tables`));
    const tableIssues = compareTables(srcTables, tgtTables, srcDb, tgtDb);
    if (tableIssues === 0) console.log(ok('Tables & columns match'));
    totalIssues += tableIssues;

    // ── Stored Procedures ─────────────────────────────────────────────────────
    console.log(section('Stored Procedures'));
    const [srcProcs, tgtProcs] = await Promise.all([
      getStoredProcs(srcPool),
      getStoredProcs(tgtPool),
    ]);
    console.log(info(`  ${srcDb}: ${srcProcs.size} procs    ${tgtDb}: ${tgtProcs.size} procs`));
    const procIssues = compareProcs(srcProcs, tgtProcs, srcDb, tgtDb);
    if (procIssues === 0) console.log(ok('Stored procedures match'));
    totalIssues += procIssues;

    // ── Migrations ────────────────────────────────────────────────────────────
    console.log(section('migration_history'));
    const [srcMigs, tgtMigs] = await Promise.all([
      getMigrations(srcPool),
      getMigrations(tgtPool),
    ]);

    if (srcMigs === null) {
      console.log(`  ${C.yellow}⚠${C.reset}  No migration_history table in ${srcDb}`);
    } else if (tgtMigs === null) {
      console.log(`  ${C.yellow}⚠${C.reset}  No migration_history table in ${tgtDb}`);
    } else {
      let migIssues = 0;
      for (const m of srcMigs) {
        if (!tgtMigs.has(m)) {
          console.log(missing(`Migration [${m}] applied in ${srcDb} but NOT in ${tgtDb}`));
          migIssues++;
        }
      }
      for (const m of tgtMigs) {
        if (!srcMigs.has(m)) {
          console.log(extra(`Migration [${m}] applied in ${tgtDb} but NOT in ${srcDb}`));
          migIssues++;
        }
      }
      if (migIssues === 0) console.log(ok(`Both DBs have ${srcMigs.size} migrations applied`));
      totalIssues += migIssues;
    }

  } finally {
    await srcPool.close();
    await tgtPool.close();
  }

  return { srcDb, tgtDb, connected: true, issues: totalIssues };
}

// ─── Dynamic AppDB list from GlobalDB registry ───────────────────────────────

const GLOBAL_DEV  = process.env.GLOBAL_DB_NAME      || 'DevLegacyLinkGlobal';
const GLOBAL_PROD = process.env.GLOBAL_DB_NAME_PROD  || 'LegacyLinkGlobal';
const APP_DEV     = process.env.APP_DB_NAME          || 'DevLegacyLinkApp';

// Reads all unique prod AppDBs from LegacyLinkGlobal.teams
// (excludes DevLegacyLinkApp — that's the dev reference DB)
async function getProdAppDbs() {
  let pool;
  try {
    pool = await connectTo(GLOBAL_PROD);
    const result = await pool.request().query(`
      SELECT DISTINCT app_db, name, abbr
      FROM dbo.teams
      WHERE ISNULL(app_db, '') <> ''
        AND app_db <> '${APP_DEV}'
      ORDER BY app_db
    `);
    return result.recordset; // [{ app_db, name, abbr }]
  } finally {
    if (pool) await pool.close();
  }
}

// ─── Main ─────────────────────────────────────────────────────────────────────

const argv = process.argv.slice(2);
const FLAG_GLOBAL_ONLY = argv.includes('--global-only');
const FLAG_APP_ONLY    = argv.includes('--app-only');

async function main() {
  console.log(`\n${C.bold}${C.cyan}╔══════════════════════════════════════════╗${C.reset}`);
  console.log(`${C.bold}${C.cyan}║   ll-db-deploy  Schema Compare           ║${C.reset}`);
  console.log(`${C.bold}${C.cyan}╚══════════════════════════════════════════╝${C.reset}`);
  console.log(`${C.cyan}ℹ${C.reset} Server: ${serverName}\n`);

  const results = [];

  // ── Global DB comparison (always one pair) ───────────────────────────────────
  if (!FLAG_APP_ONLY) {
    const result = await compare(GLOBAL_DEV, GLOBAL_PROD);
    results.push(result);
    console.log('');
  }

  // ── App DB comparisons (one per registered prod team) ────────────────────────
  if (!FLAG_GLOBAL_ONLY) {
    let prodAppDbs;
    try {
      prodAppDbs = await getProdAppDbs();
    } catch (err) {
      console.error(`\n${C.red}✘${C.reset} ${C.red}Failed to read team registry from ${GLOBAL_PROD}: ${err.message}${C.reset}\n`);
      process.exit(1);
    }

    if (prodAppDbs.length === 0) {
      console.log(`${C.yellow}⚠${C.reset}  No prod AppDBs found in ${GLOBAL_PROD}.teams — skipping app comparison\n`);
    } else {
      // Deduplicate: multiple teams can share the same app_db
      const seen = new Set();
      for (const { app_db, name, abbr } of prodAppDbs) {
        if (seen.has(app_db)) continue;
        seen.add(app_db);
        console.log(info(`Team: ${name} (${abbr})`));
        const result = await compare(APP_DEV, app_db);
        results.push(result);
        console.log('');
      }
    }
  }

  // ── Overall summary ──────────────────────────────────────────────────────────
  console.log(head('═══ Schema Compare Summary ═══'));
  console.log(rule());

  let allClean = true;
  for (const r of results) {
    const label = `${r.srcDb}  →  ${r.tgtDb}`;
    if (!r.connected) {
      console.log(`  ${C.red}✘${C.reset} ${label}  ${C.red}(connection failed)${C.reset}`);
      allClean = false;
    } else if (r.issues === 0) {
      console.log(`  ${C.green}✔${C.reset} ${label}  ${C.green}clean${C.reset}`);
    } else {
      console.log(`  ${C.red}✘${C.reset} ${label}  ${C.red}${r.issues} issue(s)${C.reset}`);
      allClean = false;
    }
  }

  console.log(rule());
  if (allClean) {
    console.log(`\n${C.green}${C.bold}All schemas in sync.${C.reset}\n`);
  } else {
    console.log(`\n${C.yellow}${C.bold}Schema differences found. Review above and run deploy to sync.${C.reset}\n`);
  }
}

main().catch(err => {
  console.error(`\n${C.red}✘${C.reset} ${C.red}Unexpected error: ${err.message}${C.reset}`);
  console.error(err.stack);
  process.exit(1);
});
