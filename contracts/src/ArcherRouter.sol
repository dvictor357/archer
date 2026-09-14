// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ArcherRouter — payment request links settled in native USDC on Arc.
/// @notice A payee creates a request (amount, expiry, memo). A payer settles it
///         in one transaction; funds are forwarded to the payee immediately and a
///         `Paid` event is emitted for off-chain webhooks. Arc has deterministic
///         sub-second finality, so a single `Paid` event is safe to act on.
/// @dev On Arc the native gas asset IS USDC — one pool, two views:
///        - ERC-20 view (0x3600…0000): 6 decimals. Used for all amounts, events, display.
///        - Native view (`msg.value`): 18 decimals. Used only for value transfer.
///      `amount` everywhere in this contract is the 6-decimal view (1 USDC = 1_000000).
///      `msg.value` must equal `amount * NATIVE_PER_USDC_UNIT`.
contract ArcherRouter {
    /// @dev 10^(18 - 6): converts a 6-decimal USDC amount to native wei.
    uint256 public constant NATIVE_PER_USDC_UNIT = 1e12;

    struct Request {
        address payee;
        uint64 amount; // 6-decimal USDC; max ≈ 1.8e13 USDC
        uint64 expiry; // unix seconds, 0 = never expires
        uint64 paidAt; // 0 = unpaid
        address payer;
        bytes32 memoHash; // keccak256 of off-chain memo / order id
    }

    mapping(bytes32 id => Request) public requests;
    mapping(address payee => uint256) public nonces;

    event RequestCreated(bytes32 indexed id, address indexed payee, uint64 amount, uint64 expiry, bytes32 memoHash);
    event Paid(bytes32 indexed id, address indexed payer, address indexed payee, uint64 amount);
    event Cancelled(bytes32 indexed id);
    event Refunded(bytes32 indexed id, address indexed payee, address indexed payer, uint64 amount);

    error ZeroAmount();
    error ExpiryInPast(uint64 expiry, uint256 nowTs);
    error UnknownRequest(bytes32 id);
    error AlreadyPaid(bytes32 id);
    error NotPaid(bytes32 id);
    error Expired(bytes32 id, uint64 expiry);
    error WrongValue(uint256 sent, uint256 expected);
    error NotPayee(address caller, address payee);
    error TransferFailed(address to, uint256 amount);

    /// @notice Create a payment request. `amount` is 6-decimal USDC.
    ///         Returns a deterministic id derived from (payee, nonce) so links
    ///         can be pre-computed off-chain.
    function createRequest(uint64 amount, uint64 expiry, bytes32 memoHash) external returns (bytes32 id) {
        if (amount == 0) revert ZeroAmount();
        if (expiry != 0 && expiry <= block.timestamp) revert ExpiryInPast(expiry, block.timestamp);

        uint256 nonce = nonces[msg.sender]++;
        id = requestId(msg.sender, nonce);

        requests[id] = Request({
            payee: msg.sender,
            amount: amount,
            expiry: expiry,
            paidAt: 0,
            payer: address(0),
            memoHash: memoHash
        });

        emit RequestCreated(id, msg.sender, amount, expiry, memoHash);
    }

    /// @notice Settle a request. `msg.value` (18-dec native) must equal
    ///         `amount * 1e12` exactly.
    function pay(bytes32 id) external payable {
        Request storage r = requests[id];
        if (r.payee == address(0)) revert UnknownRequest(id);
        if (r.paidAt != 0) revert AlreadyPaid(id);
        if (r.expiry != 0 && block.timestamp > r.expiry) revert Expired(id, r.expiry);
        uint256 expected = toNative(r.amount);
        if (msg.value != expected) revert WrongValue(msg.value, expected);

        // Effects before interaction (CEI).
        r.paidAt = uint64(block.timestamp);
        r.payer = msg.sender;

        _send(r.payee, msg.value);
        emit Paid(id, msg.sender, r.payee, r.amount);
    }

    /// @notice Payee cancels an unpaid request so the link stops working.
    function cancel(bytes32 id) external {
        Request storage r = requests[id];
        if (r.payee == address(0)) revert UnknownRequest(id);
        if (r.payee != msg.sender) revert NotPayee(msg.sender, r.payee);
        if (r.paidAt != 0) revert AlreadyPaid(id);

        delete requests[id];
        emit Cancelled(id);
    }

    /// @notice Payee returns funds to the payer. Payee must send the exact
    ///         native value back through this function so the refund is
    ///         recorded on-chain.
    function refund(bytes32 id) external payable {
        Request storage r = requests[id];
        if (r.payee == address(0)) revert UnknownRequest(id);
        if (r.payee != msg.sender) revert NotPayee(msg.sender, r.payee);
        if (r.paidAt == 0) revert NotPaid(id);
        uint256 expected = toNative(r.amount);
        if (msg.value != expected) revert WrongValue(msg.value, expected);

        address payer = r.payer;
        uint64 amount = r.amount;
        delete requests[id];

        _send(payer, msg.value);
        emit Refunded(id, msg.sender, payer, amount);
    }

    function requestId(address payee, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(payee, nonce));
    }

    /// @notice Convert a 6-decimal USDC amount to the 18-decimal native value.
    function toNative(uint64 amount) public pure returns (uint256) {
        return uint256(amount) * NATIVE_PER_USDC_UNIT;
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed(to, amount);
    }
}
