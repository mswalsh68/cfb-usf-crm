import sql from 'mssql';

export interface DbTarget {
  server:    string;
  database:  string;
  user?:     string;
  password?: string;
  encrypt:   boolean;
  trustCert: boolean;
}

// ─── Output parameter type system ─────────────────────────────
// Keeps mssql types internal to the db package.
// API layer never imports sql directly.
export type OutputType =
  | 'int' | 'smallint' | 'tinyint' | 'bigint'
  | 'nvarchar' | 'nvarchar50' | 'nvarchar100' | 'nvarcharmax'
  | 'uniqueidentifier'
  | 'bit' | 'decimal' | 'datetime2' | 'date';

const OUTPUT_TYPES: Record<OutputType, sql.ISqlType | (() => sql.ISqlType)> = {
  int:              sql.Int,
  smallint:         sql.SmallInt,
  tinyint:          sql.TinyInt,
  bigint:           sql.BigInt,
  nvarchar:         sql.NVarChar(sql.MAX),
  nvarchar50:       sql.NVarChar(50),
  nvarchar100:      sql.NVarChar(100),
  nvarcharmax:      sql.NVarChar(sql.MAX),
  uniqueidentifier: sql.UniqueIdentifier,
  bit:              sql.Bit,
  decimal:          sql.Decimal(10, 2),
  datetime2:        sql.DateTime2,
  date:             sql.Date,
};

export interface ExecResult<T = Record<string, unknown>> {
  rows:         T[];
  sets:         T[][];
  output:       Record<string, unknown>;
  rowsAffected: number[];
}

// ─── Connection pool cache ─────────────────────────────────────
const pools = new Map<string, sql.ConnectionPool>();

async function getPool(target: DbTarget): Promise<sql.ConnectionPool> {
  const key = `${target.server}::${target.database}`;
  const existing = pools.get(key);
  if (existing?.connected) return existing;
  if (existing) pools.delete(key); // stale — remove before reconnecting

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

  pool.on('error', (err) => {
    console.error(`[DB] Pool error on ${target.database}:`, err);
    pools.delete(key);
  });

  return pool;
}

// ─── Public API ────────────────────────────────────────────────

/**
 * Creates a tenant-scoped database executor.
 *
 * This is the ONLY sanctioned way to interact with a tenant database.
 * All data operations must flow through execute().
 * No other code in the application is permitted to execute database operations.
 */
export function createExecutor(target: DbTarget) {
  return {
    /**
     * Execute a stored procedure.
     *
     * @param procedureName - SP name, e.g. 'dbo.sp_GetPlayers'
     * @param inputs        - Input parameters (types auto-detected by mssql)
     * @param outputs       - Output parameter names mapped to their SQL type string
     *
     * @example
     * const { rows, output } = await db.execute(
     *   'dbo.sp_GetPlayers',
     *   { Search: 'Smith', Page: 1, PageSize: 50 },
     *   { TotalCount: 'int' }
     * );
     */
    async execute<T = Record<string, unknown>>(
      procedureName: string,
      inputs:  Record<string, unknown>    = {},
      outputs: Record<string, OutputType> = {}
    ): Promise<ExecResult<T>> {
      const pool = await getPool(target);
      const req  = pool.request();

      for (const [key, value] of Object.entries(inputs)) {
        req.input(key, value);
      }
      for (const [name, type] of Object.entries(outputs)) {
        req.output(name, OUTPUT_TYPES[type]);
      }

      const result = await req.execute(procedureName);
      return {
        rows:         result.recordset  as T[],
        sets:         result.recordsets as T[][],
        output:       result.output     as Record<string, unknown>,
        rowsAffected: result.rowsAffected,
      };
    },
  };
}

/**
 * Returns a raw connection pool for use in health checks only.
 * Do NOT use this for data operations — use createExecutor(target).execute() instead.
 */
export async function getClientDb(target: DbTarget): Promise<sql.ConnectionPool> {
  return getPool(target);
}

/**
 * mssql re-export for health-check use only.
 * Application code must NOT import sql directly — use createExecutor instead.
 */
export { sql };
