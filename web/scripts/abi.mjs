// Regenerate src/lib/abi.ts from the Foundry artifact. Run after `forge build`.
import { readFileSync, writeFileSync } from "node:fs";

const artifact = JSON.parse(readFileSync(new URL("../../contracts/out/ArcherRouter.sol/ArcherRouter.json", import.meta.url)));
const out = new URL("../src/lib/abi.ts", import.meta.url);
writeFileSync(
  out,
  "// Generated from contracts/out/ArcherRouter.sol/ArcherRouter.json — run `pnpm abi` to refresh.\n" +
    `export const archerRouterAbi = ${JSON.stringify(artifact.abi, null, 2)} as const;\n`,
);
console.log(`abi.ts: ${artifact.abi.length} entries`);
