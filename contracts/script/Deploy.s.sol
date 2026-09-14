// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";

/// Usage:
///   forge script script/Deploy.s.sol --rpc-url arc_testnet --broadcast
///   forge script script/Deploy.s.sol --rpc-url arc_mainnet --broadcast
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        ArcherRouter router = new ArcherRouter();
        vm.stopBroadcast();

        console.log("chain id  :", block.chainid);
        console.log("ArcherRouter:", address(router));
    }
}
