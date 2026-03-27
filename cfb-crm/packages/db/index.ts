import sql from 'mssql';

export interface DbTarget {
  server:    string;
  database:  string;
  user?:     string;
  password?: string;
  encrypt:   boolean;
  trustCert: boolean;
}

// Cache pools by "server::database" so we don't reconnect on every request
const pools = new Map<string, sql.ConnectionPool>();

export async function getClientDb(target: DbTarget): Promise<sql.ConnectionPool> {
  const key = `${target.server}::${target.database}`;
  const existing = pools.get(key);
  if (existing?.connected) return existing;
  if (existing) pools.delete(key); // stale pool — remove before reconnecting

  const config: sql.config = {
    server:   target.server,
    database: target.database,
    authentication: process.env.NODE_ENV === 'development'
      ? { type: 'default', options: { userName: target.user!, password: target.password! } }
      : { type: 'azure-active-directory-default', options: {} },
    options: {
      encrypt:                target.encrypt,
      trustServerCertificate: target.trustCert,
      enableArithAbort:       true,
    },
    pool: { max: 10, min: 0, idleTimeoutMillis: 30000 },
  };

  const pool = await sql.connect(config);
  pools.set(key, pool);
  console.log(`[DB] Connected to ${target.database} on ${target.server}`);
  return pool;
}

export { sql };
