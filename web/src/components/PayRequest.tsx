"use client";

import { useEffect, useMemo, useState } from "react";
import type { Hex } from "viem";
import {
  useAccount,
  useReadContract,
  useSignTypedData,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { TxStatus } from "./TxStatus";
import { explorerUrl } from "@/lib/chains";
import { buildAuthorization, receiveWithAuthorizationTypes, usdcDomain } from "@/lib/eip3009";
import { archerRouterAbi, getRouterAddress, isUnknown, type RequestTuple } from "@/lib/router";
import { formatUsdc, toNative } from "@/lib/usdc";

type RelayState =
  | { kind: "idle" }
  | { kind: "signing" }
  | { kind: "relaying" }
  | { kind: "done"; hash: Hex }
  | { kind: "error"; message: string };

export function PayRequest({ id }: { id: Hex }) {
  const { address, isConnected } = useAccount();
  // Snapshot once on mount; expiry is checked again on-chain anyway.
  const [now] = useState(() => BigInt(Math.floor(Date.now() / 1000)));
  const [relay, setRelay] = useState<RelayState>({ kind: "idle" });

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
  const { signTypedDataAsync } = useSignTypedData();

  useEffect(() => {
    if (isSuccess || relay.kind === "done") void refetch();
  }, [isSuccess, relay.kind, refetch]);

  if (!router) return <p className="text-amber-300">Router not deployed for this network.</p>;
  if (isLoading || !data) return <p className="text-zinc-400">Loading request…</p>;

  const r = data as RequestTuple;
  if (isUnknown(r)) return <p className="text-zinc-400">Request not found (cancelled, refunded, or never created).</p>;

  const [payee, amount, expiry, paidAt, payer] = r;
  const expired = expiry !== 0n && now > expiry;
  const paid = paidAt !== 0n;
  const busy = isPending || isConfirming || relay.kind === "signing" || relay.kind === "relaying";

  function payNative() {
    if (!router) return;
    writeContract({
      address: router,
      abi: archerRouterAbi,
      functionName: "pay",
      args: [id],
      value: toNative(amount), // 6-dec USDC -> 18-dec native msg.value
    });
  }

  async function signAndRelay() {
    if (!router || !address) return;
    setRelay({ kind: "signing" });
    try {
      // nonce = request id, to = router. See lib/eip3009.ts for why both matter.
      const auth = buildAuthorization({
        from: address,
        router,
        requestId: id,
        amount6: amount,
        nowSeconds: BigInt(Math.floor(Date.now() / 1000)),
      });
      const signature = await signTypedDataAsync({
        domain: usdcDomain,
        types: receiveWithAuthorizationTypes,
        primaryType: "ReceiveWithAuthorization",
        message: auth,
      });

      setRelay({ kind: "relaying" });
      const res = await fetch("/api/relay", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          id,
          from: auth.from,
          validAfter: auth.validAfter.toString(),
          validBefore: auth.validBefore.toString(),
          nonce: auth.nonce,
          signature,
        }),
      });
      const body = (await res.json()) as { hash?: Hex; status?: string; error?: string };
      if (!res.ok || body.status !== "success" || !body.hash) {
        setRelay({ kind: "error", message: body.error ?? `relay failed (${res.status})` });
        return;
      }
      setRelay({ kind: "done", hash: body.hash });
    } catch (e) {
      const msg = (e as { shortMessage?: string }).shortMessage ?? (e as Error).message;
      setRelay({ kind: "error", message: msg });
    }
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
        <div className="grid gap-3 sm:grid-cols-2">
          <button
            onClick={signAndRelay}
            disabled={!isConnected || busy}
            className="rounded-md bg-zinc-100 px-4 py-2.5 font-medium text-zinc-900 hover:bg-white disabled:opacity-40"
          >
            {!isConnected ? "Connect wallet" : "Sign & pay (no gas)"}
          </button>
          <button
            onClick={payNative}
            disabled={!isConnected || busy}
            className="rounded-md border border-zinc-600 px-4 py-2.5 font-medium text-zinc-100 hover:border-zinc-400 disabled:opacity-40"
          >
            Pay with transaction
          </button>
        </div>
      )}

      <TxStatus hash={hash} isPending={isPending} isConfirming={isConfirming} isSuccess={isSuccess} error={error} />
      <RelayStatus state={relay} />
    </div>
  );
}

function RelayStatus({ state }: { state: RelayState }) {
  switch (state.kind) {
    case "idle":
      return null;
    case "signing":
      return <p className="text-sm text-zinc-400">Sign the authorization in your wallet…</p>;
    case "relaying":
      return <p className="text-sm text-zinc-400">Relaying to Arc…</p>;
    case "done":
      return (
        <p className="text-sm text-emerald-400">
          Settled via relayer.{" "}
          <a href={`${explorerUrl}/tx/${state.hash}`} target="_blank" rel="noreferrer" className="underline">
            View on Arcscan
          </a>
        </p>
      );
    case "error":
      return (
        <p className="break-all rounded-md border border-red-900 bg-red-950/40 p-3 text-sm text-red-300">{state.message}</p>
      );
  }
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-0.5 sm:flex-row sm:gap-4">
      <dt className="w-20 shrink-0 text-zinc-500">{label}</dt>
      <dd className="break-all">{children}</dd>
    </div>
  );
}
