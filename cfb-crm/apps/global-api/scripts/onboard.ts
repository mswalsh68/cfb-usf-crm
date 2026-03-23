#!/usr/bin/env ts-node
/**
 * onboard.ts — provision a new client admin account + invite link
 *
 * Usage (run from apps/global-api):
 *   npm run onboard -- --email=coach@myteam.com --firstName=John --lastName=Doe
 *   npm run onboard -- --email=coach@myteam.com --firstName=John --lastName=Doe --appUrl=https://myapp.com
 *
 * What it does:
 *   1. Creates a global_admin user in CfbGlobal (no password yet)
 *   2. Generates a 7-day invite token
 *   3. Prints the /accept-invite link to send to the client
 *      → Client clicks it, sets their own password, and they're in
 *
 * If the email already exists it skips creation and just issues a fresh invite.
 */

import 'dotenv/config';
import crypto from 'crypto';
import sql    from 'mssql';

// ── DB config — mirrors src/db.ts, always uses SQL auth (script runs locally) ──
const dbConfig: sql.config = {
  server:   process.env.GLOBAL_DB_SERVER!,
  database: process.env.GLOBAL_DB_NAME!,
  authentication: {
    type: 'default',
    options: {
      userName: process.env.GLOBAL_DB_USER!,
      password: process.env.GLOBAL_DB_PASS!,
    },
  },
  options: {
    encrypt:                false,
    trustServerCertificate: process.env.GLOBAL_DB_TRUST_CERT === 'true',
    enableArithAbort:       true,
  },
};

// ── Arg helpers ──────────────────────────────────────────────────────────────
function getArg(name: string, required = true): string | undefined {
  const flag = `--${name}=`;
  const arg  = process.argv.find(a => a.startsWith(flag));
  if (!arg && required) {
    console.error(`\n❌  Missing required argument: --${name}\n`);
    console.error('Usage: npm run onboard -- --email=<email> --firstName=<first> --lastName=<last>\n');
    process.exit(1);
  }
  return arg ? arg.slice(flag.length) : undefined;
}

const email     = getArg('email')!.trim().toLowerCase();
const firstName = getArg('firstName')!.trim();
const lastName  = getArg('lastName')!.trim();
const appUrl    = getArg('appUrl', false) ?? 'http://localhost:3000';

// System actor ID used in audit log when there is no human actor
const SYSTEM_ID = '00000000-0000-0000-0000-000000000000';

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  console.log('\n🏈  CFB-CRM Client Onboarding');
  console.log('══════════════════════════════');
  console.log(`  Email      : ${email}`);
  console.log(`  Name       : ${firstName} ${lastName}`);
  console.log(`  App URL    : ${appUrl}`);
  console.log('');

  const pool = await sql.connect(dbConfig);
  console.log('  ✅ Connected to CfbGlobal\n');

  // ── Step 1: create the user (no password — invite sets it) ───────────────
  let userId: string;

  const createReq = pool.request();
  createReq.input ('Email',        sql.NVarChar(255),    email);
  createReq.input ('PasswordHash', sql.NVarChar(255),    'INVITE_PENDING');
  createReq.input ('FirstName',    sql.NVarChar(100),    firstName);
  createReq.input ('LastName',     sql.NVarChar(100),    lastName);
  createReq.input ('GlobalRole',   sql.NVarChar(50),     'global_admin');
  createReq.input ('CreatedBy',    sql.UniqueIdentifier, SYSTEM_ID);
  createReq.output('NewUserId',    sql.UniqueIdentifier);
  createReq.output('ErrorCode',    sql.NVarChar(50));

  const createResult = await createReq.execute('dbo.sp_CreateUser');
  const { ErrorCode, NewUserId } = createResult.output;

  if (ErrorCode === 'EMAIL_ALREADY_EXISTS') {
    console.log('  ⚠️  User already exists — generating a fresh invite link.\n');
    const existing = await pool.request()
      .input('Email', sql.NVarChar(255), email)
      .query('SELECT CAST(id AS NVARCHAR(50)) AS id FROM dbo.users WHERE email = @Email');
    userId = existing.recordset[0]?.id;
    if (!userId) { console.error('❌  Could not fetch existing user ID.'); process.exit(1); }
  } else if (ErrorCode) {
    console.error(`❌  Failed to create user: ${ErrorCode}`);
    process.exit(1);
  } else {
    userId = NewUserId;
    console.log(`  ✅ Admin account created  (id: ${userId})`);
  }

  // ── Step 2: generate invite token ────────────────────────────────────────
  const rawToken  = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7 days

  await pool.request()
    .input('UserId',    sql.UniqueIdentifier, userId)
    .input('TokenHash', sql.VarChar(128),     tokenHash)
    .input('ExpiresAt', sql.DateTime2,        expiresAt)
    .execute('dbo.sp_CreateInviteToken');

  console.log('  ✅ Invite token created\n');

  // ── Step 3: print the invite link ────────────────────────────────────────
  const inviteUrl = `${appUrl}/accept-invite?token=${rawToken}`;

  console.log('══════════════════════════════════════════════════════════════');
  console.log('');
  console.log('  📧  Send this link to your client:');
  console.log('');
  console.log(`      ${inviteUrl}`);
  console.log('');
  console.log(`  ⏰  Expires : ${expiresAt.toUTCString()}`);
  console.log('');
  console.log('  The client clicks the link, sets their password, and logs in.');
  console.log('  They can then create all other users from the Admin panel.');
  console.log('');
  console.log('══════════════════════════════════════════════════════════════\n');

  await pool.close();
}

main().catch(err => {
  console.error('\n❌  Unexpected error:', err.message ?? err);
  process.exit(1);
});
