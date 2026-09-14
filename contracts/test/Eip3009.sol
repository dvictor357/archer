// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Vm} from "forge-std/Vm.sol";

/// @dev Test helper: builds and signs a ReceiveWithAuthorization for a given USDC domain.
library Eip3009 {
    bytes32 internal constant TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    struct Auth {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    function sign(Vm vm, bytes32 domainSeparator, Auth memory a, uint256 pk)
        internal
        pure
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash =
            keccak256(abi.encode(TYPEHASH, a.from, a.to, a.value, a.validAfter, a.validBefore, a.nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (v, r, s) = vm.sign(pk, digest);
    }
}
