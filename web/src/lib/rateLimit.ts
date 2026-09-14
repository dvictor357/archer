/**
 * Fixed-window rate limiter, in-memory. First line of defense for /api/relay,
 * where the relayer pays gas for every accepted request.
 *
 * Scope: per server instance. On a single Node process this is exact; on
 * serverless/multi-instance deployments each instance keeps its own counters,
 * so treat these limits as "per instance" and put edge rate limiting (CDN /
 * proxy) in front for hard guarantees.
 */

type Window = { count: number; resetAt: number };

const buckets = new Map<string, Window>();
let lastPrune = 0;

export type RateLimitResult = { ok: true } | { ok: false; retryAfterSeconds: number };

export function rateLimit(key: string, limit: number, windowMs: number, now = Date.now()): RateLimitResult {
  if (now - lastPrune > windowMs) {
    for (const [k, w] of buckets) if (w.resetAt <= now) buckets.delete(k);
    lastPrune = now;
  }

  const w = buckets.get(key);
  if (!w || w.resetAt <= now) {
    buckets.set(key, { count: 1, resetAt: now + windowMs });
    return { ok: true };
  }
  if (w.count >= limit) {
    return { ok: false, retryAfterSeconds: Math.max(1, Math.ceil((w.resetAt - now) / 1000)) };
  }
  w.count++;
  return { ok: true };
}

/** First hop of X-Forwarded-For, else a constant so limits still apply. */
export function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]!.trim();
  return req.headers.get("x-real-ip") ?? "unknown";
}

/** Test hook. */
export function _resetRateLimits() {
  buckets.clear();
  lastPrune = 0;
}
