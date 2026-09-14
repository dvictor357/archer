# Archer

**Aim. Release. Settled.** — Payment request links settled in native USDC on [Arc](https://arc.io).

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

## Contracts

```sh
cd contracts
cp .env.example .env         # fill PRIVATE_KEY
forge test
forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast
```

Native USDC on Arc uses **18 decimals**. `amount` everywhere is wei-USDC (`1 USDC = 1e18`).

### ArcherRouter

| Function | Who | Effect |
|---|---|---|
| `createRequest(amount, expiry, memoHash)` | payee | returns deterministic `id = keccak256(payee, nonce)` |
| `pay(id)` payable | anyone | `msg.value == amount`, forwards to payee, emits `Paid` |
| `cancel(id)` | payee | deletes unpaid request |
| `refund(id)` payable | payee | returns exact amount to payer, emits `Refunded` |

## Roadmap

- [x] Router contract + tests
- [ ] Deploy testnet, record address in `chains.json`
- [ ] Web: create link / pay page / `Paid` webhook listener
- [ ] CCTP: pay from another chain
- [ ] `ArcherEscrow` (held funds, conditional release)
- [ ] `ArcherAgent` (spending-policy wallet for AI agents)
- [ ] Mainnet day-1 redeploy (16 Sep 2026)
