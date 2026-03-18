import sql from 'mssql';

const config: sql.config = {
  server:   process.env.ROSTER_DB_SERVER!,
  database: process.env.ROSTER_DB_NAME!,
  authentication: {
    type: 'azure-active-directory-default', // Uses managed identity in Azure
    options: {},
  },
};

let pool: sql.ConnectionPool | null = null;

export async function getDb(): Promise<sql.ConnectionPool> {
  if (pool?.connected) return pool;
  pool = await sql.connect(config);
  console.log('[Roster DB] Connected');
  return pool;
}

export { sql };
