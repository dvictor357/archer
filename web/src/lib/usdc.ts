import { formatUnits, parseUnits } from "viem";

/**
 * USDC on Arc is ONE pool with TWO views:
 *   - ERC-20 view: 6 decimals. All amounts, display, events.
 *   - Native view (msg.value / gas): 18 decimals.
 * Every conversion goes through this file so the 10^12 factor lives in one place.
 */
export const USDC_DECIMALS = 6;
export const NATIVE_DECIMALS = 18;
export const NATIVE_PER_USDC_UNIT = 10n ** BigInt(NATIVE_DECIMALS - USDC_DECIMALS); // 1e12

/** "25.5" -> 25_500000n (6-dec) */
export function parseUsdc(human: string): bigint {
  return parseUnits(human, USDC_DECIMALS);
}

/** 25_500000n (6-dec) -> "25.5" */
export function formatUsdc(amount6: bigint): string {
  return formatUnits(amount6, USDC_DECIMALS);
}

/** 6-dec amount -> 18-dec native value for msg.value. Mirrors ArcherRouter.toNative. */
export function toNative(amount6: bigint): bigint {
  return amount6 * NATIVE_PER_USDC_UNIT;
}

/** 18-dec native balance -> "25.5" for display. Only for wallet native balance reads. */
export function formatNativeAsUsdc(native18: bigint): string {
  return formatUnits(native18, NATIVE_DECIMALS);
}
