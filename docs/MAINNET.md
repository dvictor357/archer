# Mainnet day-1 runbook

Target: Arc mainnet, 16 Sep 2026. Reported chain id `1243`. Official RPC / explorer / USDC address
are published at launch — **verify every value on-chain before deploying** (chain id, `USDC.decimals()`
= 6, `USDC.version()` = "2", `DOMAIN_SEPARATOR()` matches name `USDC` / version `2` / chain id / address).

## 0. Before launch (do now)

- [ ] Relayer wallet for mainnet: `cast wallet new`. Fund with ~$5 USDC when mainnet USDC is available.
- [ ] Deployer keystore funded: `cast wallet address --account archer` → send ~$3 USDC for deploy gas.
- [ ] `forge fmt` everything (src/ was kept byte-identical to the verified testnet deploy).

## 1. Sanity-check the network

```sh
export ARC_MAINNET_RPC=<official rpc>
cast chain-id --rpc-url $ARC_MAINNET_RPC                     # expect 1243
cast call <USDC> "decimals()(uint8)" --rpc-url $ARC_MAINNET_RPC   # expect 6
cast call <USDC> "version()(string)" --rpc-url $ARC_MAINNET_RPC   # expect "2"
cast call <USDC> "DOMAIN_SEPARATOR()(bytes32)" --rpc-url $ARC_MAINNET_RPC
cast keccak $(cast abi-encode 'f(bytes32,bytes32,bytes32,uint256,address)' \
  $(cast keccak "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)") \
  $(cast keccak "USDC") $(cast keccak "2") 1243 <USDC>)        # must equal the line above
```

If USDC is not `0x3600000000000000000000000000000000000000` on mainnet, pass `USDC_ADDRESS=<addr>` to the deploy.

## 2. Deploy + verify

```sh
cd contracts
forge fmt && forge test
forge script script/Deploy.s.sol --rpc-url arc_mainnet --account archer --broadcast
forge verify-contract <ROUTER> src/ArcherRouter.sol:ArcherRouter \
  --verifier blockscout --verifier-url <explorer>/api --chain-id 1243 \
  --constructor-args $(cast abi-encode "constructor(address)" <USDC>) --watch
forge verify-bytecode <ROUTER> src/ArcherRouter.sol:ArcherRouter \
  --rpc-url $ARC_MAINNET_RPC --verifier blockscout --verifier-url <explorer>/api
```

## 3. Config

- [ ] `chains.json` → `arcMainnet`: `rpc`, `ws`, `explorer`, `usdc.address`, `eurc.address`, `cctpDomain`, `router`
- [ ] Vercel env: `NEXT_PUBLIC_ARC_NETWORK=arcMainnet`, `RELAYER_PRIVATE_KEY=<mainnet relayer>`
- [ ] Redeploy web. Smoke test: create 0.10 USDC request → Sign & pay → `Paid` on explorer.
- [ ] `pnpm listen` against mainnet `ws` to confirm the webhook path.

## 4. Announce

- [ ] README: swap testnet router/tx for mainnet, keep testnet in a "Testnet" line.
- [ ] X reply to the launch thread + Arc House + Discord `#showcase`: mainnet address, first mainnet tx.

## Rollback

Nothing to roll back on-chain — the router holds no funds. If a bug is found, deploy a fixed router,
update `chains.json`, redeploy web. Old links keep resolving against the old router (read-only).
