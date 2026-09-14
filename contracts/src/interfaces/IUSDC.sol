// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Subset of Circle's FiatTokenV2 used by ArcherRouter.
interface IUSDC {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);

    /// @notice EIP-3009. Pulls `value` from `from` into `to`. FiatTokenV2 requires
    ///         `to == msg.sender`, which is what makes this front-run safe.
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
