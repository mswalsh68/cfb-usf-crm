import sql from 'mssql';

const config: sql.config = {
  server:   process.env.ALUMNI_DB_SERVER!,
  database: process.env.ALUMNI_DB_NAME!,
  authentication: process.env.NODE_ENV === 'development'
    ? { type: 'default', options: { userName: process.env.ALUMNI_DB_USER!, password: process.env.ALUMNI_DB_PASS! } }
    : { type: 'azure-active-directory-default', options: {} },
  options: {
    encrypt:               process.env.ALUMNI_DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.ALUMNI_DB_TRUST_CERT === 'true',
    enableArithAbort:      true,
  },
  pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
};

let pool: sql.ConnectionPool | null = null;

export async function getDb(): Promise<sql.ConnectionPool> {
  if (pool?.connected) return pool;
  pool = await sql.connect(config);
  console.log('[Alumni DB] Connected');
  return pool;
}

export { sql };