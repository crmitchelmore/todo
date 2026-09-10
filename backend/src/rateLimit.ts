import { rateLimit } from 'express-rate-limit';

/** Per-client API budget, before JSON parsing and database/authentication work. */
export function apiRateLimiter(limit = 120) {
  return rateLimit({
    windowMs: 60_000,
    limit,
    standardHeaders: 'draft-8',
    legacyHeaders: false,
    message: { error: 'Too many requests. Please retry shortly.' },
  });
}
