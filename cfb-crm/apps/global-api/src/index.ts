import 'dotenv/config';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { authRouter } from './routes/auth';
import { usersRouter, permissionsRouter } from './routes/users';
import { healthRouter } from './routes/health';
import { configRouter } from './routes/config';
import { platformRouter } from './routes/platform';

const app = express();
const PORT = process.env.PORT || 3001;

app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') ?? ['http://localhost:8081'],
  credentials: true,
}));

const globalLimiter      = rateLimit({ windowMs: 15 * 60 * 1000, max: 200 });
// Strict limiter for login/register only (brute-force protection)
const authLimiter        = rateLimit({ windowMs: 15 * 60 * 1000, max: 10,  message: 'Too many auth attempts, please try again later' });
// Relaxed limiter for switch-team — legitimate users switch frequently
const switchTeamLimiter  = rateLimit({ windowMs: 15 * 60 * 1000, max: 100, message: 'Too many team switch requests' });

app.use(globalLimiter);
app.use(express.json({ limit: '10kb' }));

// Request logging
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () =>
    console.log(`[Global API] ${req.method} ${req.path} ${res.statusCode} ${Date.now() - start}ms`));
  next();
});

app.use('/health',      healthRouter);
app.use('/config',      configRouter);
app.use('/auth/switch-team', switchTeamLimiter);
app.use('/auth',             authLimiter, authRouter);
app.use('/users',       usersRouter);
app.use('/permissions', permissionsRouter);
app.use('/platform',    platformRouter);

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