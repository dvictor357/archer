// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";

/// Signer comes from an encrypted Foundry keystore, never a plaintext key:
///   cast wallet import archer --interactive
///   forge script script/Deploy.s.sol --rpc-url arc_testnet --account archer --broadcast
///   forge script script/Deploy.s.sol --rpc-url arc_mainnet --account archer --broadcast
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        ArcherRouter router = new ArcherRouter();
        vm.stopBroadcast();

        console.log("chain id    :", block.chainid);
        console.log("ArcherRouter:", address(router));
    }
}
