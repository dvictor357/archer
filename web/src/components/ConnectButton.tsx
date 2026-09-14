"use client";

import { useAccount, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { activeChain } from "@/lib/chains";

function short(addr: string) {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function ConnectButton() {
  const { address, chainId, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain, isPending: switching } = useSwitchChain();

  if (!isConnected || !address) {
    const injected = connectors[0];
    return (
      <button
        onClick={() => injected && connect({ connector: injected })}
        disabled={!injected || isPending}
        className="rounded-md bg-zinc-100 px-3 py-1.5 text-sm font-medium text-zinc-900 hover:bg-white disabled:opacity-50"
      >
        {isPending ? "Connecting…" : "Connect wallet"}
      </button>
    );
  }

  if (chainId !== activeChain.id) {
    return (
      <button
        onClick={() => switchChain({ chainId: activeChain.id })}
        disabled={switching}
        className="rounded-md bg-amber-400 px-3 py-1.5 text-sm font-medium text-zinc-900 hover:bg-amber-300 disabled:opacity-50"
      >
        {switching ? "Switching…" : `Switch to ${activeChain.name}`}
      </button>
    );
  }

  return (
    <button
      onClick={() => disconnect()}
      title="Disconnect"
      className="rounded-md border border-zinc-700 px-3 py-1.5 font-mono text-sm text-zinc-300 hover:border-zinc-500"
    >
      {short(address)}
    </button>
  );
}
