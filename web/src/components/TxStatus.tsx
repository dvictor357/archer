"use client";

import { explorerUrl } from "@/lib/chains";

export function TxStatus({
  hash,
  isPending,
  isConfirming,
  isSuccess,
  error,
}: {
  hash?: `0x${string}`;
  isPending: boolean;
  isConfirming: boolean;
  isSuccess: boolean;
  error?: Error | null;
}) {
  if (error) {
    return (
      <p className="break-all rounded-md border border-red-900 bg-red-950/40 p-3 text-sm text-red-300">
        {(error as { shortMessage?: string }).shortMessage ?? error.message}
      </p>
    );
  }
  if (isPending) return <p className="text-sm text-zinc-400">Confirm in wallet…</p>;
  if (isConfirming) return <p className="text-sm text-zinc-400">Settling on Arc…</p>;
  if (isSuccess && hash) {
    return (
      <p className="text-sm text-emerald-400">
        Settled.{" "}
        <a href={`${explorerUrl}/tx/${hash}`} target="_blank" rel="noreferrer" className="underline">
          View on Arcscan
        </a>
      </p>
    );
  }
  return null;
}
