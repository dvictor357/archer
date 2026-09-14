/**
 * Webhook demo: subscribe to ArcherRouter `Paid` events over WebSocket and
 * POST each one to WEBHOOK_URL. On Arc a single event is final — no
 * confirmation counting.
 *
 *   pnpm listen                       # log only
 *   WEBHOOK_URL=http://localhost:4000/hook pnpm listen
 */
import { createPublicClient, webSocket, formatUnits } from "viem";
import { arcTestnet } from "viem/chains";
import chains from "../../chains.json" with { type: "json" };
import { archerRouterAbi } from "../src/lib/abi.ts";

const cfg = chains.arcTestnet;
if (!cfg.router) throw new Error("chains.json arcTestnet.router is empty");

const client = createPublicClient({ chain: arcTestnet, transport: webSocket(cfg.ws) });
const webhook = process.env.WEBHOOK_URL;

console.log(`listening Paid on ${cfg.router} via ${cfg.ws}`);

client.watchContractEvent({
  address: cfg.router as `0x${string}`,
  abi: archerRouterAbi,
  eventName: "Paid",
  onLogs: async (logs) => {
    for (const log of logs) {
      const { id, payer, payee, amount } = log.args;
      const payload = {
        event: "Paid",
        id,
        payer,
        payee,
        amountUsdc: formatUnits(amount!, cfg.usdc.decimals),
        amountRaw6: amount!.toString(),
        txHash: log.transactionHash,
        block: log.blockNumber?.toString(),
        chainId: cfg.id,
      };
      console.log(JSON.stringify(payload));
      if (webhook) {
        try {
          const res = await fetch(webhook, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify(payload),
          });
          if (!res.ok) console.error(`webhook ${webhook} responded ${res.status}`);
        } catch (err) {
          console.error(`webhook ${webhook} failed:`, (err as Error).message);
        }
      }
    }
  },
  onError: (err) => console.error("subscription error:", err.message),
});
