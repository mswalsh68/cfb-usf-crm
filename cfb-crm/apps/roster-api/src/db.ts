// Multi-tenant DB connections are handled via getClientDb() in @cfb-crm/db.
// This file provides a server-level pool used only for the /health endpoint.
import { getClientDb, sql } from '@cfb-crm/db';

export async function getHealthDb() {
  return getClientDb({
    server:    process.env.DB_SERVER!,
    database:  'master',
    user:      process.env.DB_USER,
    password:  process.env.DB_PASS,
    encrypt:   process.env.DB_ENCRYPT === 'true',
    trustCert: process.env.DB_TRUST_CERT === 'true',
  });
}

export { sql };
