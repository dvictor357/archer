"use client";

import { useMemo, useState } from "react";
import { keccak256, stringToHex, type Hex } from "viem";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { TxStatus } from "./TxStatus";
import { archerRouterAbi, computeRequestId, getRouterAddress } from "@/lib/router";
import { parseUsdc } from "@/lib/usdc";

export function CreateRequest() {
  const { address, isConnected } = useAccount();
  const [amount, setAmount] = useState("");
  const [memo, setMemo] = useState("");
  const [expiryHours, setExpiryHours] = useState("24");
  // Nonce captured at submit time so the id we derive matches the tx exactly.
  const [nonceAtSubmit, setNonceAtSubmit] = useState<bigint | null>(null);

  const router = useMemo(() => {
    try {
      return getRouterAddress();
    } catch {
      return null;
    }
  }, []);

  // Nonce lets us compute the request id client-side before the tx lands.
  const { data: nonce } = useReadContract({
    address: router ?? undefined,
    abi: archerRouterAbi,
    functionName: "nonces",
    args: address ? [address] : undefined,
    query: { enabled: !!router && !!address },
  });

  const { writeContract, data: hash, isPending, error, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash });

  const createdId: Hex | null =
    isSuccess && address && nonceAtSubmit !== null ? computeRequestId(address, nonceAtSubmit) : null;

  const amount6 = useMemo(() => {
    try {
      return amount ? parseUsdc(amount) : 0n;
    } catch {
      return null;
    }
  }, [amount]);
  const amountValid = amount6 !== null && amount6 > 0n && amount6 <= 2n ** 64n - 1n;

  function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!router || !amountValid || amount6 === null || nonce === undefined) return;
    const hours = Number(expiryHours);
    const expiry = hours > 0 ? BigInt(Math.floor(Date.now() / 1000) + hours * 3600) : 0n;
    const memoHash = keccak256(stringToHex(memo));
    setNonceAtSubmit(nonce);
    reset();
    writeContract({
      address: router,
      abi: archerRouterAbi,
      functionName: "createRequest",
      args: [amount6, expiry, memoHash],
    });
  }

  if (!router) {
    return (
      <p className="rounded-md border border-amber-900 bg-amber-950/40 p-3 text-sm text-amber-300">
        Router not deployed for this network. Fill <code>router</code> in <code>chains.json</code>.
      </p>
    );
  }

  const link = createdId && typeof window !== "undefined" ? `${window.location.origin}/pay/${createdId}` : null;

  return (
    <form onSubmit={submit} className="space-y-5 rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <Field label="Amount (USDC)">
        <input
          inputMode="decimal"
          placeholder="25.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className={inputCls}
        />
      </Field>
      <Field label="Memo (order id, invoice, note)">
        <input value={memo} onChange={(e) => setMemo(e.target.value)} placeholder="INV-0042" className={inputCls} />
        <p className="mt-1 text-xs text-zinc-500">Only the keccak256 hash goes on-chain.</p>
      </Field>
      <Field label="Expires in (hours, 0 = never)">
        <input
          inputMode="numeric"
          value={expiryHours}
          onChange={(e) => setExpiryHours(e.target.value)}
          className={inputCls}
        />
      </Field>

      <button
        type="submit"
        disabled={!isConnected || !amountValid || nonce === undefined || isPending || isConfirming}
        className="w-full rounded-md bg-zinc-100 px-4 py-2.5 font-medium text-zinc-900 hover:bg-white disabled:opacity-40"
      >
        {!isConnected ? "Connect wallet first" : "Create payment link"}
      </button>

      <TxStatus hash={hash} isPending={isPending} isConfirming={isConfirming} isSuccess={isSuccess} error={error} />

      {link && (
        <div className="space-y-2 rounded-md border border-emerald-900 bg-emerald-950/30 p-4">
          <p className="text-sm text-emerald-300">Share this link:</p>
          <div className="flex gap-2">
            <input readOnly value={link} className={`${inputCls} font-mono text-xs`} onFocus={(e) => e.target.select()} />
            <button
              type="button"
              onClick={() => navigator.clipboard.writeText(link)}
              className="shrink-0 rounded-md border border-zinc-700 px-3 text-sm hover:border-zinc-500"
            >
              Copy
            </button>
          </div>
        </div>
      )}
    </form>
  );
}

const inputCls =
  "w-full rounded-md border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-100 outline-none focus:border-zinc-400";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm text-zinc-400">{label}</span>
      {children}
    </label>
  );
}
