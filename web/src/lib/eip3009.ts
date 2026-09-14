import type { Address, Hex, TypedDataDomain } from "viem";
import { activeChain, activeConfig } from "./chains";

/**
 * EIP-3009 ReceiveWithAuthorization for USDC on Arc.
 *
 * Security invariants (mirrored in ArcherRouter.payWithAuthorization):
 *   - `to` is always the router — FiatTokenV2 requires msg.sender == to, so only
 *     the router can consume the signature. Never sign a TransferWithAuthorization.
 *   - `nonce` is always the request id — the router rejects anything else, so a
 *     signature cannot be replayed against another request of equal amount.
 *   - `value` is the request amount in the 6-decimal ERC-20 view.
 */
export const usdcDomain: TypedDataDomain = {
  name: "USDC",
  version: "2",
  chainId: activeChain.id,
  verifyingContract: activeConfig.usdc.address as Address,
};

export const receiveWithAuthorizationTypes = {
  ReceiveWithAuthorization: [
    { name: "from", type: "address" },
    { name: "to", type: "address" },
    { name: "value", type: "uint256" },
    { name: "validAfter", type: "uint256" },
    { name: "validBefore", type: "uint256" },
    { name: "nonce", type: "bytes32" },
  ],
} as const;

export type ReceiveAuthorization = {
  from: Address;
  to: Address;
  value: bigint;
  validAfter: bigint;
  validBefore: bigint;
  nonce: Hex;
};

/** Authorization window: 10 minutes. Short on purpose — a signature is a bearer instrument until it expires. */
export const AUTH_TTL_SECONDS = 600n;

export function buildAuthorization(args: {
  from: Address;
  router: Address;
  requestId: Hex;
  amount6: bigint;
  nowSeconds: bigint;
}): ReceiveAuthorization {
  return {
    from: args.from,
    to: args.router,
    value: args.amount6,
    validAfter: 0n,
    validBefore: args.nowSeconds + AUTH_TTL_SECONDS,
    nonce: args.requestId,
  };
}
