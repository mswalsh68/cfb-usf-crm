#!/usr/bin/env node
'use strict';

/**
 * release.js — LegacyLink slot-swap deployment
 *
 * Merges the current dev branch into main, pulls the prod codebase
 * up to date, installs dependencies, and optionally pushes DB
 * migrations to all prod AppDBs.
 *
 * Usage:
 *   node scripts/release.js            # merge + pull prod + install
 *   node scripts/release.js --db-only  # push DB changes to prod only (no code)
 *   node scripts/release.js --dry-run  # preview steps without executing
 */

const { execSync } = require('child_process');
const path = require('path');
const fs   = require('fs');

// ─── Config ──────────────────────────────────────────────────
const PROD_DIR    = path.resolve(__dirname, '..', '..', '..', 'cfb-usf-crm-prod', 'cfb-crm');
const DEPLOY_DIR  = path.resolve(__dirname, '..', '..', '..', 'll-db-deploy');
const APPS        = ['apps/global-api', 'apps/app-api', 'apps/web'];

const C = {
  reset:  '\x1b[0m',
  bold:   '\x1b[1m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
};
const ok   = (s) => console.log(`${C.green}✔${C.reset} ${s}`);
const info = (s) => console.log(`${C.cyan}ℹ${C.reset} ${s}`);
const warn = (s) => console.log(`${C.yellow}⚠${C.reset}  ${s}`);
const fail = (s) => console.log(`${C.red}✘${C.reset} ${C.red}${s}${C.reset}`);
const head = (s) => console.log(`\n${C.bold}${s}${C.reset}`);

const argv    = process.argv.slice(2);
const DRY_RUN = argv.includes('--dry-run');
const DB_ONLY = argv.includes('--db-only');

function run(cmd, cwd) {
  if (DRY_RUN) {
    console.log(`  ${C.yellow}(dry-run)${C.reset} ${cmd}  ${cwd ? C.cyan + '[' + cwd + ']' + C.reset : ''}`);
    return '';
  }
  try {
    return execSync(cmd, { cwd, stdio: 'pipe', encoding: 'utf8' }).trim();
  } catch (err) {
    throw new Error(`Command failed: ${cmd}\n${err.stderr || err.message}`);
  }
}

// ─── Preflight checks ─────────────────────────────────────────
function preflight() {
  if (!fs.existsSync(PROD_DIR)) {
    fail(`Prod directory not found: ${PROD_DIR}`);
    fail('Run: git clone https://github.com/mswalsh68/cfb-usf-crm.git cfb-usf-crm-prod');
    process.exit(1);
  }
  if (!fs.existsSync(DEPLOY_DIR)) {
    warn(`ll-db-deploy not found at ${DEPLOY_DIR} — DB migrations will be skipped`);
  }
  ok('Preflight checks passed');
}

// ─── Step 1: Check dev working tree is clean ─────────────────
function checkDevClean() {
  head('Step 1 — Check dev working tree');
  const devRoot = path.resolve(__dirname, '..', '..');
  const status = run('git status --porcelain', devRoot);
  if (status && status.length > 0) {
    fail('Dev working tree has uncommitted changes. Commit or stash first.');
    console.log(status);
    process.exit(1);
  }
  ok('Dev working tree is clean');
}

// ─── Step 2: Merge current branch → main, push to both remotes ──
function mergeToMain() {
  head('Step 2 — Merge dev → main');
  const devRoot = path.resolve(__dirname, '..', '..');
  const branch = run('git rev-parse --abbrev-ref HEAD', devRoot);
  info(`Current branch: ${branch}`);

  if (branch !== 'main') {
    run('git checkout main', devRoot);
    run(`git merge ${branch} --no-ff -m "release: merge ${branch} → main"`, devRoot);
    run(`git checkout ${branch}`, devRoot);
  } else {
    warn('Already on main');
  }

  // Push main to DevLegacyLink (dev origin)
  run('git push origin main', devRoot);
  ok('Pushed main → DevLegacyLink');

  // Push main to ProdLegacyLink if the remote exists
  const remotes = run('git remote', devRoot);
  if (remotes.includes('prod')) {
    run('git push prod main', devRoot);
    ok('Pushed main → ProdLegacyLink');
  } else {
    warn('No "prod" remote found on dev repo — skipping ProdLegacyLink push');
    warn('Add it once: git remote add prod https://github.com/mswalsh68/ProdLegacyLink.git');
  }
}

// ─── Step 3: Pull prod codebase ───────────────────────────────
function pullProd() {
  head('Step 3 — Pull prod codebase');
  const prodRoot = path.resolve(PROD_DIR, '..', '..');
  run('git checkout main', prodRoot);
  run('git pull origin main', prodRoot);
  ok('Prod codebase is up to date');
}

// ─── Step 4: Install dependencies in prod ────────────────────
function installProd() {
  head('Step 4 — Install dependencies (prod)');
  for (const app of APPS) {
    const appDir = path.join(PROD_DIR, app);
    if (!fs.existsSync(appDir)) {
      warn(`App directory not found, skipping: ${app}`);
      continue;
    }
    info(`npm install → ${app}`);
    run('npm install --prefer-offline', appDir);
    ok(app);
  }
}

// ─── Step 5: Push DB migrations to prod AppDBs ────────────────
function deployProdDb() {
  head('Step 5 — Deploy DB migrations to prod AppDBs');
  if (!fs.existsSync(DEPLOY_DIR)) {
    warn('ll-db-deploy not found — skipping DB step');
    return;
  }
  run('node deploy.js --env prod --all', DEPLOY_DIR);
  ok('Prod AppDB migrations complete');
}

// ─── Main ─────────────────────────────────────────────────────
function main() {
  console.log(`\n${C.bold}${C.cyan}╔══════════════════════════════════════╗${C.reset}`);
  console.log(`${C.bold}${C.cyan}║   LegacyLink Release  (slot swap)    ║${C.reset}`);
  console.log(`${C.bold}${C.cyan}╚══════════════════════════════════════╝${C.reset}`);

  if (DRY_RUN) warn('DRY RUN — no changes will be made');

  try {
    preflight();

    if (DB_ONLY) {
      deployProdDb();
    } else {
      checkDevClean();
      mergeToMain();
      pullProd();
      installProd();
      deployProdDb();
    }

    console.log(`\n${C.green}${C.bold}Release complete.${C.reset}`);
    console.log(`${C.cyan}ℹ${C.reset}  Restart prod services to pick up the new code.\n`);
  } catch (err) {
    fail(err.message);
    process.exit(1);
  }
}

main();
