// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ArcherRouter — payment request links settled in native USDC on Arc.
/// @notice A payee creates a request (amount, expiry, memo). A payer settles it
///         in one transaction; funds are forwarded to the payee immediately and a
///         `Paid` event is emitted for off-chain webhooks. Arc has deterministic
///         sub-second finality, so a single `Paid` event is safe to act on.
/// @dev Native balance on Arc is USDC with 18 decimals — `amount` is in wei-USDC.
contract ArcherRouter {
    struct Request {
        address payee;
        uint96 amount; // wei-USDC; 96 bits ≈ 7.9e28 > any realistic invoice
        uint64 expiry; // unix seconds, 0 = never expires
        uint64 paidAt; // 0 = unpaid
        address payer;
        bytes32 memoHash; // keccak256 of off-chain memo / order id
    }

    mapping(bytes32 id => Request) public requests;
    mapping(address payee => uint256) public nonces;

    event RequestCreated(bytes32 indexed id, address indexed payee, uint96 amount, uint64 expiry, bytes32 memoHash);
    event Paid(bytes32 indexed id, address indexed payer, address indexed payee, uint96 amount);
    event Cancelled(bytes32 indexed id);
    event Refunded(bytes32 indexed id, address indexed payee, address indexed payer, uint96 amount);

    error ZeroAmount();
    error ExpiryInPast(uint64 expiry, uint256 nowTs);
    error UnknownRequest(bytes32 id);
    error AlreadyPaid(bytes32 id);
    error NotPaid(bytes32 id);
    error Expired(bytes32 id, uint64 expiry);
    error WrongAmount(uint256 sent, uint96 expected);
    error NotPayee(address caller, address payee);
    error TransferFailed(address to, uint256 amount);

    /// @notice Create a payment request. Returns a deterministic id derived from
    ///         (payee, nonce) so links can be pre-computed off-chain.
    function createRequest(uint96 amount, uint64 expiry, bytes32 memoHash) external returns (bytes32 id) {
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

    /// @notice Settle a request. `msg.value` must equal the requested amount exactly.
    function pay(bytes32 id) external payable {
        Request storage r = requests[id];
        if (r.payee == address(0)) revert UnknownRequest(id);
        if (r.paidAt != 0) revert AlreadyPaid(id);
        if (r.expiry != 0 && block.timestamp > r.expiry) revert Expired(id, r.expiry);
        if (msg.value != r.amount) revert WrongAmount(msg.value, r.amount);

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

    /// @notice Payee returns funds to the payer. Payee must send the exact amount
    ///         back through this function so the refund is recorded on-chain.
    function refund(bytes32 id) external payable {
        Request storage r = requests[id];
        if (r.payee == address(0)) revert UnknownRequest(id);
        if (r.payee != msg.sender) revert NotPayee(msg.sender, r.payee);
        if (r.paidAt == 0) revert NotPaid(id);
        if (msg.value != r.amount) revert WrongAmount(msg.value, r.amount);

        address payer = r.payer;
        uint96 amount = r.amount;
        delete requests[id];

        _send(payer, msg.value);
        emit Refunded(id, msg.sender, payer, amount);
    }

    function requestId(address payee, uint256 nonce) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(payee, nonce));
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed(to, amount);
    }
}
