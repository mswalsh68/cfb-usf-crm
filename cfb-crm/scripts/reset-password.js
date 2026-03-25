/**
 * One-time script: reset a user's password
 * Usage: node scripts/reset-password.js
 */
const bcrypt   = require('bcryptjs');
const mssql    = require('mssql');
require('dotenv').config({ path: './apps/global-api/.env' });

const EMAIL    = 'mswalsh68@gmail.com';
const PASSWORD = '$USFbulls68';

async function main() {
  const hash = await bcrypt.hash(PASSWORD, 12);
  console.log('Generated hash:', hash);

  const pool = await mssql.connect({
    server:   process.env.GLOBAL_DB_SERVER  || 'localhost\\SQLEXPRESS',
    database: process.env.GLOBAL_DB_NAME    || 'CfbGlobal',
    options:  { encrypt: false, trustServerCertificate: true },
    authentication: {
      type:    'default',
      options: {
        userName: process.env.GLOBAL_DB_USER || '',
        password: process.env.GLOBAL_DB_PASS || '',
      },
    },
  });

  const result = await pool.request()
    .input('Hash',  mssql.NVarChar, hash)
    .input('Email', mssql.NVarChar, EMAIL)
    .query(`UPDATE dbo.users
            SET    password_hash = @Hash,
                   updated_at    = SYSUTCDATETIME()
            WHERE  email = @Email`);

  console.log('Rows updated:', result.rowsAffected[0]);

  // Verify
  const check = await pool.request()
    .input('Email', mssql.NVarChar, EMAIL)
    .query('SELECT LEFT(password_hash, 10) AS HashPrefix FROM dbo.users WHERE email = @Email');
  console.log('Stored hash prefix:', check.recordset[0]?.HashPrefix);

  await pool.close();
}

main().catch(console.error);
