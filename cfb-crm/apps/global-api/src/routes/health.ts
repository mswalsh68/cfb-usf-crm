import { Router } from 'express';
import { getDb } from '../db';

export const healthRouter = Router();

healthRouter.get('/', async (_req, res) => {
  try {
    const db = await getDb();
    await db.request().query('SELECT 1');
    res.json({ success: true, service: 'global-api', db: 'connected', ts: new Date().toISOString() });
  } catch {
    res.status(503).json({ success: false, service: 'global-api', db: 'disconnected' });
  }
});
