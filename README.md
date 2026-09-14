# Archer

**Aim. Release. Settled.** — Payment request links settled in USDC on [Arc](https://arc.network).

A payee creates a request (amount, expiry, memo) and shares a link. The payer settles it in
one transaction. Funds are forwarded to the payee immediately and a `Paid` event fires — Arc's
deterministic sub-second finality means a backend can act on that single event without waiting
for confirmations.

## Layout

```
contracts/   Foundry — ArcherRouter.sol + tests + deploy script
web/         Next.js + viem — pay link UI (WIP)
chains.json  Shared chain config (testnet 5042002 / mainnet 1243). Deployed router addresses live here.
```

## USDC on Arc: one pool, two views

The native gas asset on Arc **is** USDC. Same funds, two interfaces:

| View | Decimals | Used for |
|---|---|---|
| ERC-20 `0x3600000000000000000000000000000000000000` | 6 | balances, display, events, `amount` in ArcherRouter |
| Native (`msg.value`, gas) | 18 | value transfer only |

`ArcherRouter` takes `amount` in the 6-decimal view (`25 USDC = 25_000000`) and requires
`msg.value == amount * 1e12`. Never add the two views together or treat them as separate assets.

## Contracts

```sh
cd contracts
forge test

# one-time: encrypted keystore for the deployer (never a plaintext key)
cast wallet import archer --interactive

forge script script/Deploy.s.sol --rpc-url arc_testnet --account archer --broadcast
```

Fund the deployer from https://faucet.circle.com first.

### ArcherRouter

| Function | Who | Effect |
|---|---|---|
| `createRequest(amount, expiry, memoHash)` | payee | returns deterministic `id = keccak256(payee, nonce)` |
| `pay(id)` payable | anyone | `msg.value == toNative(amount)`, forwards to payee, emits `Paid` |
| `cancel(id)` | payee | deletes unpaid request |
| `refund(id)` payable | payee | returns exact value to payer, emits `Refunded` |
| `toNative(amount)` | view | 6-dec USDC → 18-dec native wei |

## Roadmap

- [x] Router contract + tests
- [ ] Deploy testnet, record address in `chains.json`
- [ ] Web: create link / pay page / `Paid` webhook listener (wss)
- [ ] CCTP (domain 26): pay from another chain
- [ ] `ArcherEscrow` (held funds, conditional release)
- [ ] `ArcherAgent` (spending-policy wallet for AI agents, x402)
- [ ] Mainnet day-1 redeploy (16 Sep 2026)
