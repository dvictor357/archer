"use client";

import { useEffect, useMemo, useState } from "react";
import type { Hex } from "viem";
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { TxStatus } from "./TxStatus";
import { explorerUrl } from "@/lib/chains";
import { archerRouterAbi, getRouterAddress, isUnknown, type RequestTuple } from "@/lib/router";
import { formatUsdc, toNative } from "@/lib/usdc";

export function PayRequest({ id }: { id: Hex }) {
  const { isConnected } = useAccount();
  // Snapshot once on mount; expiry is checked again on-chain anyway.
  const [now] = useState(() => BigInt(Math.floor(Date.now() / 1000)));
  const router = useMemo(() => {
    try {
      return getRouterAddress();
    } catch {
      return null;
    }
  }, []);

  const { data, isLoading, refetch } = useReadContract({
    address: router ?? undefined,
    abi: archerRouterAbi,
    functionName: "requests",
    args: [id],
    query: { enabled: !!router },
  });

  const { writeContract, data: hash, isPending, error } = useWriteContract();
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({
    hash,
    query: { enabled: !!hash },
  });

  useEffect(() => {
    if (isSuccess) void refetch();
  }, [isSuccess, refetch]);

  if (!router) return <p className="text-amber-300">Router not deployed for this network.</p>;
  if (isLoading || !data) return <p className="text-zinc-400">Loading request…</p>;

  const r = data as RequestTuple;
  if (isUnknown(r)) return <p className="text-zinc-400">Request not found (cancelled, refunded, or never created).</p>;

  const [payee, amount, expiry, paidAt, payer] = r;
  const expired = expiry !== 0n && now > expiry;
  const paid = paidAt !== 0n;

  function pay() {
    if (!router) return;
    writeContract({
      address: router,
      abi: archerRouterAbi,
      functionName: "pay",
      args: [id],
      value: toNative(amount), // 6-dec USDC -> 18-dec native msg.value
    });
  }

  return (
    <div className="space-y-6 rounded-xl border border-zinc-800 bg-zinc-900/50 p-6">
      <div>
        <p className="text-sm text-zinc-400">Payment request</p>
        <p className="mt-1 text-4xl font-semibold tracking-tight">
          {formatUsdc(amount)} <span className="text-2xl text-zinc-400">USDC</span>
        </p>
      </div>

      <dl className="space-y-2 text-sm">
        <Row label="To">
          <a href={`${explorerUrl}/address/${payee}`} target="_blank" rel="noreferrer" className="font-mono underline">
            {payee}
          </a>
        </Row>
        <Row label="Expires">{expiry === 0n ? "Never" : new Date(Number(expiry) * 1000).toLocaleString()}</Row>
        <Row label="Status">
          {paid ? (
            <span className="text-emerald-400">
              Paid by <span className="font-mono">{payer}</span>
            </span>
          ) : expired ? (
            <span className="text-red-400">Expired</span>
          ) : (
            <span className="text-amber-300">Awaiting payment</span>
          )}
        </Row>
      </dl>

      {!paid && !expired && (
        <button
          onClick={pay}
          disabled={!isConnected || isPending || isConfirming}
          className="w-full rounded-md bg-zinc-100 px-4 py-2.5 font-medium text-zinc-900 hover:bg-white disabled:opacity-40"
        >
          {!isConnected ? "Connect wallet to pay" : `Pay ${formatUsdc(amount)} USDC`}
        </button>
      )}

      <TxStatus hash={hash} isPending={isPending} isConfirming={isConfirming} isSuccess={isSuccess} error={error} />
    </div>
  );
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5 sm:flex-row sm:gap-4">
      <dt className="w-20 shrink-0 text-zinc-500">{label}</dt>
      <dd className="break-all">{children}</dd>
    </div>
  );
}
