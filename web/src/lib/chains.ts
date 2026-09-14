import { arcTestnet } from "viem/chains";
import { defineChain, type Chain } from "viem";
import chainsJson from "../../../chains.json";

/**
 * Single source of truth for chain config lives in ../chains.json (shared with
 * contracts/). viem already ships `arcTestnet`; mainnet is defined here from
 * chains.json and becomes usable once its rpc/router fields are filled in.
 */
export const chains = chainsJson;

export const arcMainnet: Chain = defineChain({
  id: chains.arcMainnet.id,
  name: chains.arcMainnet.name,
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: chains.arcMainnet.nativeDecimals },
  rpcUrls: {
    default: {
      http: chains.arcMainnet.rpc ? [chains.arcMainnet.rpc] : [],
      webSocket: chains.arcMainnet.ws ? [chains.arcMainnet.ws] : [],
    },
  },
  blockExplorers: chains.arcMainnet.explorer
    ? { default: { name: "Arcscan", url: chains.arcMainnet.explorer } }
    : undefined,
});

export type ChainKey = "arcTestnet" | "arcMainnet";

/** NEXT_PUBLIC_ARC_NETWORK=arcMainnet flips the whole app to mainnet. */
export const activeKey: ChainKey =
  process.env.NEXT_PUBLIC_ARC_NETWORK === "arcMainnet" ? "arcMainnet" : "arcTestnet";

export const activeChain: Chain = activeKey === "arcMainnet" ? arcMainnet : arcTestnet;
export const activeConfig = chains[activeKey];

export const routerAddress = activeConfig.router as `0x${string}` | "";
export const explorerUrl = activeConfig.explorer;
