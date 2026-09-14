// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";
import {IUSDC} from "../src/interfaces/IUSDC.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {Eip3009} from "./Eip3009.sol";

/// Unit tests for the EIP-3009 payment path against a FiatTokenV2-faithful mock.
contract ArcherRouterAuthorizationTest is Test {
    ArcherRouter router;
    MockUSDC usdc;

    uint256 constant PAYER_PK = 0xA11CE;
    address payer;
    address payee = makeAddr("payee");
    address relayer = makeAddr("relayer");
    address attacker = makeAddr("attacker");

    uint64 constant AMOUNT = 25_000000; // 25 USDC
    bytes32 constant MEMO = keccak256("order-123");

    event Paid(bytes32 indexed id, address indexed payer, address indexed payee, uint64 amount);

    function setUp() public {
        payer = vm.addr(PAYER_PK);
        usdc = new MockUSDC();
        router = new ArcherRouter(IUSDC(address(usdc)));
        usdc.mint(payer, 1000_000000);
        vm.warp(1_700_000_000);
    }

    function _create(address who, uint64 amount, uint64 expiry) internal returns (bytes32 id) {
        vm.prank(who);
        id = router.createRequest(amount, expiry, MEMO);
    }

    function _auth(bytes32 id, uint256 value) internal view returns (Eip3009.Auth memory a) {
        a = Eip3009.Auth({
            from: payer,
            to: address(router),
            value: value,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: id
        });
    }

    function _sign(Eip3009.Auth memory a) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return Eip3009.sign(vm, usdc.DOMAIN_SEPARATOR(), a, PAYER_PK);
    }

    // ---- happy path ----

    function test_payWithAuthorization_settlesAndRecordsSigner() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.expectEmit(true, true, true, true);
        emit Paid(id, payer, payee, AMOUNT);

        vm.prank(relayer); // anyone can relay; payer stays the signer
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);

        assertEq(usdc.balanceOf(payee), AMOUNT);
        assertEq(usdc.balanceOf(payer), 1000_000000 - AMOUNT);
        assertEq(usdc.balanceOf(address(router)), 0);
        (,,, uint64 paidAt, address recordedPayer,) = router.requests(id);
        assertEq(paidAt, block.timestamp);
        assertEq(recordedPayer, payer);
        assertTrue(usdc.authorizationState(payer, id));
    }

    // ---- security: replay to another request ----

    /// Attacker creates a request with the same amount and tries to consume the
    /// payer's signature against it. Router rejects: nonce must equal the id.
    function test_payWithAuthorization_revertsWhenNonceIsNotTheId() public {
        bytes32 victimId = _create(payee, AMOUNT, 0);
        bytes32 attackerId = _create(attacker, AMOUNT, 0);

        Eip3009.Auth memory a = _auth(victimId, AMOUNT); // signed for victimId
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AuthorizationNonceMismatch.selector, victimId, attackerId));
        router.payWithAuthorization(attackerId, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);

        assertEq(usdc.balanceOf(attacker), 0);
    }

    /// Attacker passes nonce == attackerId to satisfy the router check; the
    /// signature was over victimId so USDC's ecrecover fails.
    function test_payWithAuthorization_revertsWhenSignatureIsForAnotherRequest() public {
        bytes32 victimId = _create(payee, AMOUNT, 0);
        bytes32 attackerId = _create(attacker, AMOUNT, 0);

        Eip3009.Auth memory a = _auth(victimId, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.prank(attacker);
        vm.expectRevert("FiatTokenV2: invalid signature");
        router.payWithAuthorization(attackerId, payer, a.validAfter, a.validBefore, attackerId, v, r, s);
    }

    // ---- security: front-run via bare transfer is impossible ----

    /// A non-router caller cannot consume the authorization at all.
    function test_authorization_cannotBeConsumedOutsideRouter() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.prank(attacker);
        vm.expectRevert("FiatTokenV2: caller must be the payee");
        usdc.receiveWithAuthorization(payer, address(router), AMOUNT, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    // ---- security: value comes from storage ----

    /// Signing a smaller value than the request amount must not settle it.
    function test_payWithAuthorization_revertsWhenSignedValueDiffers() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT - 1);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.prank(relayer);
        vm.expectRevert("FiatTokenV2: invalid signature");
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    // ---- replay of the same signature ----

    function test_payWithAuthorization_revertsOnSecondUse() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);

        vm.startPrank(relayer);
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
        vm.stopPrank();
    }

    // ---- request guards apply ----

    function test_payWithAuthorization_revertsUnknown() public {
        bytes32 id = keccak256("nope");
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.UnknownRequest.selector, id));
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    function test_payWithAuthorization_revertsExpiredRequest() public {
        bytes32 id = _create(payee, AMOUNT, uint64(block.timestamp + 10));
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        vm.warp(block.timestamp + 11);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.Expired.selector, id, uint64(block.timestamp - 1)));
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    function test_payWithAuthorization_revertsExpiredAuthorization() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        a.validBefore = block.timestamp; // must be strictly in the future
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        vm.expectRevert("FiatTokenV2: authorization is expired");
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    function test_payWithAuthorization_revertsAlreadyPaidNatively() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        vm.deal(attacker, 100 ether);
        vm.prank(attacker);
        router.pay{value: router.toNative(AMOUNT)}(id);

        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
    }

    // ---- cross-path interactions ----

    function test_cancel_afterAuthorizationPaid_reverts() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);

        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.cancel(id);
    }

    function test_refund_afterAuthorizationPaid_goesToSigner() public {
        bytes32 id = _create(payee, AMOUNT, 0);
        Eip3009.Auth memory a = _auth(id, AMOUNT);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);

        uint256 native = router.toNative(AMOUNT);
        vm.deal(payee, native);
        uint256 before = payer.balance;
        vm.prank(payee);
        router.refund{value: native}(id);
        assertEq(payer.balance - before, native);
    }

    // ---- fuzz ----

    function testFuzz_payWithAuthorization_anyAmount(uint64 amount) public {
        amount = uint64(bound(amount, 1, 1000_000000));
        bytes32 id = _create(payee, amount, 0);
        Eip3009.Auth memory a = _auth(id, amount);
        (uint8 v, bytes32 r, bytes32 s) = _sign(a);
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);
        assertEq(usdc.balanceOf(payee), amount);
    }
}
