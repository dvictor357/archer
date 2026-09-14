import { encodePacked, keccak256, type Address, type Hex } from "viem";
import { archerRouterAbi } from "./abi";
import { routerAddress } from "./chains";

export { archerRouterAbi };

export function getRouterAddress(): Address {
  if (!routerAddress) {
    throw new Error(
      "ArcherRouter address not set. Deploy contracts and fill `router` in chains.json for the active network.",
    );
  }
  return routerAddress;
}

/** Mirrors ArcherRouter.requestId: keccak256(abi.encodePacked(payee, nonce)). */
export function computeRequestId(payee: Address, nonce: bigint): Hex {
  return keccak256(encodePacked(["address", "uint256"], [payee, nonce]));
}

export type RequestTuple = readonly [
  payee: Address,
  amount: bigint, // 6-dec USDC
  expiry: bigint,
  paidAt: bigint,
  payer: Address,
  memoHash: Hex,
];

export function isUnknown(r: RequestTuple): boolean {
  return r[0] === "0x0000000000000000000000000000000000000000";
}
