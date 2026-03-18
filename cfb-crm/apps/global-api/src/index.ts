import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { authRouter } from './routes/auth';
import { usersRouter, permissionsRouter } from './routes/users';
import { healthRouter } from './routes/health';

const app = express();
const PORT = process.env.PORT || 3001;

// ─── Security Middleware ─────────────────────────────────────
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') ?? ['http://localhost:8081'],
  credentials: true,
}));

// Rate limiting — tighter on auth endpoints
const globalLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 200 });
const authLimiter   = rateLimit({ windowMs: 15 * 60 * 1000, max: 20, message: 'Too many auth attempts' });

app.use(globalLimiter);
app.use(express.json({ limit: '10kb' }));

// ─── Routes ──────────────────────────────────────────────────
app.use('/health',      healthRouter);
app.use('/auth',        authLimiter, authRouter);
app.use('/users',       usersRouter);
app.use('/permissions', permissionsRouter);

// ─── 404 & Error Handling ────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ success: false, error: 'Route not found' });
});

app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('[Global API Error]', err);
  res.status(500).json({ success: false, error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`[Global API] Running on port ${PORT}`);
});

export default app;
