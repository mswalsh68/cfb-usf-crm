#!/usr/bin/env node
/**
 * LegacyLink Migration Runner
 *
 * Applies pending SQL migrations to all tenant databases.
 * Per directive section 4.9.2:
 *   - Connects to global DB to retrieve tenant list
 *   - For each tenant, checks migration_history to determine what's been applied
 *   - Applies unapplied migrations in order, within a transaction
 *   - Records each migration in migration_history with checksum
 *   - Produces a summary report
 *
 * Usage:
 *   node scripts/migration-runner.js [--dry-run] [--tenant USFBullsApp]
 */

require('dotenv').config();
const sql  = require('mssql');
const fs   = require('fs');
const path = require('path');
const crypto = require('crypto');

const DRY_RUN    = process.argv.includes('--dry-run');
const ONLY_TENANT = (() => {
  const i = process.argv.indexOf('--tenant');
  return i !== -1 ? process.argv[i + 1] : null;
})();

const MIGRATIONS_DIR = path.join(__dirname, '../databases/app/migrations');

// ─── DB connection helper ─────────────────────────────────────

async function connect(server, database) {
  const config = {
    server,
    database,
    authentication: process.env.NODE_ENV === 'development'
      ? { type: 'default', options: { userName: process.env.DB_USER, password: process.env.DB_PASS } }
      : { type: 'azure-active-directory-default', options: {} },
    options: {
      encrypt:                process.env.DB_ENCRYPT === 'true',
      trustServerCertificate: process.env.DB_TRUST_CERT === 'true',
      enableArithAbort:       true,
    },
  };
  return sql.connect(config);
}

// ─── Load migrations in order ─────────────────────────────────

function loadMigrations() {
  return fs.readdirSync(MIGRATIONS_DIR)
    .filter(f => f.endsWith('.sql'))
    .sort()  // alphabetical = chronological given NNN_ prefix
    .map(file => {
      const fullPath = path.join(MIGRATIONS_DIR, file);
      const content  = fs.readFileSync(fullPath, 'utf8').replace(/^\uFEFF/, ''); // strip BOM
      const checksum = crypto.createHash('sha256').update(content).digest('hex');
      return { name: file, content, checksum, path: fullPath };
    });
}

// ─── Get applied migrations for a tenant ─────────────────────

async function getApplied(pool) {
  try {
    const result = await pool.request().query(
      'SELECT migration_name, checksum FROM dbo.migration_history ORDER BY migration_id'
    );
    return new Map(result.recordset.map(r => [r.migration_name, r.checksum]));
  } catch {
    // migration_history table doesn't exist yet — treat as empty
    return new Map();
  }
}

// ─── Apply a single migration ─────────────────────────────────

async function applyMigration(pool, migration) {
  const start = Date.now();

  // Split on GO batch separators (SQL Server convention)
  const batches = migration.content
    .split(/^\s*GO\s*$/im)
    .map(b => b.trim())
    .filter(b => b.length > 0);

  const tx = new sql.Transaction(pool);
  await tx.begin();
  try {
    for (const batch of batches) {
      await new sql.Request(tx).query(batch);
    }

    const elapsed = Date.now() - start;
    if (!DRY_RUN) {
      await new sql.Request(tx)
        .input('name',     sql.NVarChar(200), migration.name)
        .input('checksum', sql.NVarChar(64),  migration.checksum)
        .input('ms',       sql.Int,           elapsed)
        .query(`
          INSERT INTO dbo.migration_history (migration_name, checksum, execution_time_ms)
          VALUES (@name, @checksum, @ms)
        `);
    }
    await tx.commit();
    return { success: true, elapsed };
  } catch (err) {
    await tx.rollback();
    throw err;
  }
}

// ─── Process a single tenant ──────────────────────────────────

async function processTenant(server, database) {
  const result = { database, applied: [], skipped: [], failed: [], error: null };
  let pool;
  try {
    pool = await connect(server, database);
    const migrations = loadMigrations();
    const applied    = await getApplied(pool);

    for (const migration of migrations) {
      if (applied.has(migration.name)) {
        // Checksum verification
        if (applied.get(migration.name) !== migration.checksum) {
          result.failed.push({ name: migration.name, reason: 'CHECKSUM_MISMATCH — file was modified after being applied' });
        } else {
          result.skipped.push(migration.name);
        }
        continue;
      }

      if (DRY_RUN) {
        result.applied.push(`[DRY RUN] ${migration.name}`);
        continue;
      }

      try {
        const { elapsed } = await applyMigration(pool, migration);
        result.applied.push(`${migration.name} (${elapsed}ms)`);
        console.log(`  ✓ Applied ${migration.name} in ${elapsed}ms`);
      } catch (err) {
        result.failed.push({ name: migration.name, reason: err.message });
        console.error(`  ✗ Failed ${migration.name}:`, err.message);
        break; // stop on first failure for this tenant
      }
    }
  } catch (err) {
    result.error = err.message;
  } finally {
    if (pool) await pool.close();
  }
  return result;
}

// ─── Main ─────────────────────────────────────────────────────

async function main() {
  console.log(`\n=== LegacyLink Migration Runner ${DRY_RUN ? '[DRY RUN]' : ''} ===\n`);

  // Connect to global DB to get tenant list
  let globalPool;
  try {
    globalPool = await connect(
      process.env.GLOBAL_DB_SERVER,
      process.env.GLOBAL_DB_NAME || 'LegacyLinkGlobal'
    );
  } catch (err) {
    console.error('Failed to connect to global DB:', err.message);
    process.exit(1);
  }

  // Get all active tenants
  let tenants;
  try {
    const result = await globalPool.request().query(
      `SELECT name, app_db, db_server
       FROM dbo.teams
       WHERE is_active = 1 AND app_db IS NOT NULL
       ORDER BY name`
    );
    tenants = result.recordset;
  } finally {
    await globalPool.close();
  }

  if (ONLY_TENANT) {
    tenants = tenants.filter(t => t.app_db === ONLY_TENANT);
    if (tenants.length === 0) {
      console.error(`No active tenant found with app_db = '${ONLY_TENANT}'`);
      process.exit(1);
    }
  }

  console.log(`Found ${tenants.length} tenant(s):\n`);

  const results = [];
  for (const tenant of tenants) {
    console.log(`→ ${tenant.name} (${tenant.app_db})`);
    const result = await processTenant(tenant.db_server, tenant.app_db);
    results.push({ tenant: tenant.name, ...result });
    console.log('');
  }

  // Summary report
  console.log('\n=== Migration Summary ===\n');
  let allSucceeded = true;
  for (const r of results) {
    const status = r.failed.length > 0 ? '✗ FAILED' : r.error ? '✗ ERROR' : '✓ OK';
    console.log(`${status}  ${r.tenant} (${r.database})`);
    if (r.applied.length)  console.log(`         Applied:  ${r.applied.join(', ')}`);
    if (r.skipped.length)  console.log(`         Skipped:  ${r.skipped.length} already applied`);
    if (r.failed.length) {
      allSucceeded = false;
      for (const f of r.failed) console.log(`         FAILED:   ${f.name} — ${f.reason}`);
    }
    if (r.error) {
      allSucceeded = false;
      console.log(`         ERROR:    ${r.error}`);
    }
  }

  console.log('\n' + (allSucceeded ? '✓ All tenants migrated successfully.' : '✗ Some tenants failed — check output above.'));
  process.exit(allSucceeded ? 0 : 1);
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
