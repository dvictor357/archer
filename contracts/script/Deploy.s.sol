// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";
import {IUSDC} from "../src/interfaces/IUSDC.sol";

/// Signer comes from an encrypted Foundry keystore, never a plaintext key:
///   cast wallet import archer --interactive
///   forge script script/Deploy.s.sol --rpc-url arc_testnet --account archer --broadcast
///   forge script script/Deploy.s.sol --rpc-url arc_mainnet --account archer --broadcast
contract Deploy is Script {
    /// USDC ERC-20 view on Arc. Same address is expected on mainnet; override
    /// with USDC_ADDRESS if it differs.
    address constant ARC_USDC = 0x3600000000000000000000000000000000000000;

    function run() external {
        address usdc = vm.envOr("USDC_ADDRESS", ARC_USDC);

        vm.startBroadcast();
        ArcherRouter router = new ArcherRouter(IUSDC(usdc));
        vm.stopBroadcast();

        console.log("chain id    :", block.chainid);
        console.log("USDC        :", usdc);
        console.log("ArcherRouter:", address(router));
    }
}
