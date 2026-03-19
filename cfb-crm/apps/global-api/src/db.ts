import sql from 'mssql';

const config: sql.config = {
  server:   process.env.GLOBAL_DB_SERVER!,
  database: process.env.GLOBAL_DB_NAME!,
  authentication: {
    type: 'azure-active-directory-default', // Uses managed identity in Azure
    options: {},
  },
  options: {
    encrypt:              process.env.GLOBAL_DB_ENCRYPT === 'true',
    trustServerCertificate: process.env.GLOBAL_DB_TRUST_CERT === 'true',
    enableArithAbort:     true,
  },
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
};

// For local dev, fall back to SQL auth if managed identity isn't available
if (process.env.NODE_ENV === 'development') {
  config.authentication = {
    type: 'default',
    options: {
      userName: process.env.GLOBAL_DB_USER!,
      password: process.env.GLOBAL_DB_PASS!,
    },
  };
}

let pool: sql.ConnectionPool | null = null;

export async function getDb(): Promise<sql.ConnectionPool> {
  if (pool && pool.connected) return pool;
  pool = await sql.connect(config);
  console.log('[Global DB] Connected');
  return pool;
}

export { sql };
