import { NextResponse } from "next/server";
import {
  createPublicClient,
  createWalletClient,
  http,
  isAddress,
  isHex,
  parseSignature,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { activeChain, activeConfig } from "@/lib/chains";
import { archerRouterAbi, getRouterAddress, isUnknown, type RequestTuple } from "@/lib/router";
import { AUTH_TTL_SECONDS } from "@/lib/eip3009";
import { clientIp, rateLimit } from "@/lib/rateLimit";

/**
 * Relays a signed EIP-3009 authorization to ArcherRouter.payWithAuthorization.
 * The relayer pays gas (in USDC); the signer is recorded on-chain as the payer.
 *
 * Abuse controls, cheapest first:
 *   1. Rate limits: per IP, per signer, and global (see lib/rateLimit.ts).
 *   2. Strict input shape.
 *   3. nonce must equal id (router enforces too; fail early here).
 *   4. validBefore bounded to 2x AUTH_TTL so long-lived signatures are refused.
 *   5. Request must exist, be unpaid, unexpired (read-only RPC, no gas).
 *   6. eth_call simulation before broadcasting — a bad signature never costs gas.
 * Anyone may submit a valid signature for any request; that is the product
 * (open relay). In-memory limits are per instance; add edge limiting for
 * hard guarantees.
 */

const WINDOW_MS = 60_000;
const LIMIT_PER_IP = 5;
const LIMIT_PER_SIGNER = 3;
const LIMIT_GLOBAL = 60;

export const runtime = "nodejs";

type Body = {
  id: Hex;
  from: Address;
  validAfter: string;
  validBefore: string;
  nonce: Hex;
  signature: Hex;
};

function bad(message: string, status = 400, headers?: HeadersInit) {
  return NextResponse.json({ error: message }, { status, headers });
}

function tooMany(scope: string, retryAfterSeconds: number) {
  return bad(`rate limit exceeded (${scope}); retry in ${retryAfterSeconds}s`, 429, {
    "retry-after": String(retryAfterSeconds),
  });
}

function parseBody(raw: unknown): Body | string {
  if (!raw || typeof raw !== "object") return "body must be a JSON object";
  const b = raw as Record<string, unknown>;
  const { id, from, validAfter, validBefore, nonce, signature } = b;
  if (!isHex(id) || id.length !== 66) return "id must be a 32-byte hex string";
  if (typeof from !== "string" || !isAddress(from)) return "from must be an address";
  if (typeof validAfter !== "string" || !/^\d+$/.test(validAfter)) return "validAfter must be a decimal string";
  if (typeof validBefore !== "string" || !/^\d+$/.test(validBefore)) return "validBefore must be a decimal string";
  if (!isHex(nonce) || nonce.length !== 66) return "nonce must be a 32-byte hex string";
  if (!isHex(signature) || signature.length !== 132) return "signature must be 65 bytes";
  return { id, from, validAfter, validBefore, nonce, signature };
}

/** Surface the decoded custom error (e.g. AuthorizationNonceMismatch) or USDC's revert string. */
function describeRevert(e: unknown): string {
  let cur: unknown = e;
  for (let i = 0; i < 6 && cur && typeof cur === "object"; i++) {
    const c = cur as { data?: { errorName?: string; args?: unknown[] }; reason?: string; shortMessage?: string; cause?: unknown };
    if (c.data?.errorName) {
      const args = (c.data.args ?? []).map((a) => (typeof a === "bigint" ? a.toString() : String(a))).join(", ");
      return `${c.data.errorName}(${args})`;
    }
    if (c.reason) return c.reason;
    cur = c.cause;
  }
  return (e as { shortMessage?: string }).shortMessage ?? (e as Error).message;
}

export async function POST(req: Request) {
  const relayerKey = process.env.RELAYER_PRIVATE_KEY;
  if (!relayerKey || !isHex(relayerKey) || relayerKey.length !== 66) {
    return bad("relayer not configured: set RELAYER_PRIVATE_KEY (server-side only)", 503);
  }

  let router: Address;
  try {
    router = getRouterAddress();
  } catch (e) {
    return bad((e as Error).message, 503);
  }

  const ip = rateLimit(`ip:${clientIp(req)}`, LIMIT_PER_IP, WINDOW_MS);
  if (!ip.ok) return tooMany("ip", ip.retryAfterSeconds);
  const global = rateLimit("global", LIMIT_GLOBAL, WINDOW_MS);
  if (!global.ok) return tooMany("global", global.retryAfterSeconds);

  const parsed = parseBody(await req.json().catch(() => null));
  if (typeof parsed === "string") return bad(parsed);
  const { id, from, nonce, signature } = parsed;

  const signer = rateLimit(`from:${from.toLowerCase()}`, LIMIT_PER_SIGNER, WINDOW_MS);
  if (!signer.ok) return tooMany("signer", signer.retryAfterSeconds);
  const validAfter = BigInt(parsed.validAfter);
  const validBefore = BigInt(parsed.validBefore);

  if (nonce !== id) return bad("nonce must equal request id");

  const now = BigInt(Math.floor(Date.now() / 1000));
  if (validBefore <= now) return bad("authorization expired");
  if (validBefore > now + AUTH_TTL_SECONDS * 2n) return bad("validBefore too far in the future");
  if (validAfter >= now) return bad("authorization not yet valid");

  const publicClient = createPublicClient({ chain: activeChain, transport: http(activeConfig.rpc) });

  const r = (await publicClient.readContract({
    address: router,
    abi: archerRouterAbi,
    functionName: "requests",
    args: [id],
  })) as RequestTuple;
  if (isUnknown(r)) return bad("request not found", 404);
  if (r[3] !== 0n) return bad("request already paid", 409);
  if (r[2] !== 0n && now > r[2]) return bad("request expired", 410);

  const sig = parseSignature(signature);
  if (sig.v === undefined) return bad("signature missing v");
  const args = [id, from, validAfter, validBefore, nonce, Number(sig.v), sig.r, sig.s] as const;

  const account = privateKeyToAccount(relayerKey);

  // Simulate first: a bad signature reverts here, costing nothing.
  let request;
  try {
    ({ request } = await publicClient.simulateContract({
      account,
      address: router,
      abi: archerRouterAbi,
      functionName: "payWithAuthorization",
      args,
    }));
  } catch (e) {
    return bad(`simulation failed: ${describeRevert(e)}`, 422);
  }

  const walletClient = createWalletClient({ account, chain: activeChain, transport: http(activeConfig.rpc) });
  const hash = await walletClient.writeContract(request);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  return NextResponse.json({ hash, status: receipt.status, block: receipt.blockNumber.toString() });
}
