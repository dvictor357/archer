import { test } from "node:test";
import assert from "node:assert/strict";
import { rateLimit, _resetRateLimits } from "./rateLimit.ts";

test("allows up to limit within window, then blocks with retry-after", () => {
  _resetRateLimits();
  const t0 = 1_000_000;
  for (let i = 0; i < 3; i++) assert.deepEqual(rateLimit("k", 3, 60_000, t0 + i), { ok: true });
  const blocked = rateLimit("k", 3, 60_000, t0 + 10_000);
  assert.equal(blocked.ok, false);
  if (!blocked.ok) assert.equal(blocked.retryAfterSeconds, 50);
});

test("window resets after windowMs", () => {
  _resetRateLimits();
  const t0 = 1_000_000;
  for (let i = 0; i < 3; i++) rateLimit("k", 3, 60_000, t0);
  assert.equal(rateLimit("k", 3, 60_000, t0 + 59_999).ok, false);
  assert.equal(rateLimit("k", 3, 60_000, t0 + 60_000).ok, true);
});

test("keys are independent", () => {
  _resetRateLimits();
  for (let i = 0; i < 3; i++) rateLimit("a", 3, 60_000, 0);
  assert.equal(rateLimit("a", 3, 60_000, 1).ok, false);
  assert.equal(rateLimit("b", 3, 60_000, 1).ok, true);
});
