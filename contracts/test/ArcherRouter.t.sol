// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";

contract RejectingPayee {
    receive() external payable {
        revert("no");
    }
}

contract ArcherRouterTest is Test {
    ArcherRouter router;

    address payee = makeAddr("payee");
    address payer = makeAddr("payer");
    uint64 constant AMOUNT = 25_000000; // 25 USDC, 6-decimal view
    uint256 constant AMOUNT_NATIVE = 25 ether; // same 25 USDC, 18-decimal native view
    bytes32 constant MEMO = keccak256("order-123");

    event RequestCreated(bytes32 indexed id, address indexed payee, uint64 amount, uint64 expiry, bytes32 memoHash);
    event Paid(bytes32 indexed id, address indexed payer, address indexed payee, uint64 amount);
    event Cancelled(bytes32 indexed id);
    event Refunded(bytes32 indexed id, address indexed payee, address indexed payer, uint64 amount);

    function setUp() public {
        router = new ArcherRouter();
        vm.deal(payer, 1000 ether);
    }

    function _create(uint64 expiry) internal returns (bytes32 id) {
        vm.prank(payee);
        id = router.createRequest(AMOUNT, expiry, MEMO);
    }

    // ---- decimals ----

    function test_toNative_scalesBy1e12() public view {
        assertEq(router.toNative(AMOUNT), AMOUNT_NATIVE);
        assertEq(router.toNative(1), 1e12);
        assertEq(router.toNative(type(uint64).max), uint256(type(uint64).max) * 1e12);
    }

    // ---- createRequest ----

    function test_createRequest_storesAndEmits() public {
        bytes32 expectedId = router.requestId(payee, 0);
        vm.expectEmit(true, true, false, true);
        emit RequestCreated(expectedId, payee, AMOUNT, 0, MEMO);

        bytes32 id = _create(0);
        assertEq(id, expectedId);

        (address p, uint64 amt, uint64 exp, uint64 paidAt, address pr, bytes32 memo) = router.requests(id);
        assertEq(p, payee);
        assertEq(amt, AMOUNT);
        assertEq(exp, 0);
        assertEq(paidAt, 0);
        assertEq(pr, address(0));
        assertEq(memo, MEMO);
        assertEq(router.nonces(payee), 1);
    }

    function test_createRequest_nonceIncrementsGivesDistinctIds() public {
        bytes32 a = _create(0);
        bytes32 b = _create(0);
        assertTrue(a != b);
    }

    function test_createRequest_revertsZeroAmount() public {
        vm.prank(payee);
        vm.expectRevert(ArcherRouter.ZeroAmount.selector);
        router.createRequest(0, 0, MEMO);
    }

    function test_createRequest_revertsExpiryInPast() public {
        vm.warp(1000);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.ExpiryInPast.selector, uint64(999), uint256(1000)));
        router.createRequest(AMOUNT, 999, MEMO);
    }

    // ---- pay ----

    function test_pay_forwardsFundsAndEmits() public {
        bytes32 id = _create(0);
        uint256 before = payee.balance;

        vm.expectEmit(true, true, true, true);
        emit Paid(id, payer, payee, AMOUNT);

        vm.prank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);

        assertEq(payee.balance - before, AMOUNT_NATIVE);
        assertEq(address(router).balance, 0);
        (,,, uint64 paidAt, address pr,) = router.requests(id);
        assertEq(paidAt, block.timestamp);
        assertEq(pr, payer);
    }

    function test_pay_revertsUnknown() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.UnknownRequest.selector, bytes32(0)));
        router.pay{value: AMOUNT_NATIVE}(bytes32(0));
    }

    function test_pay_revertsAlreadyPaid() public {
        bytes32 id = _create(0);
        vm.startPrank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.pay{value: AMOUNT_NATIVE}(id);
        vm.stopPrank();
    }

    function test_pay_revertsWrongValue() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongValue.selector, AMOUNT_NATIVE - 1, AMOUNT_NATIVE));
        router.pay{value: AMOUNT_NATIVE - 1}(id);
    }

    /// Sending the 6-decimal number as raw wei is the classic decimals bug — must revert.
    function test_pay_revertsIfSentSixDecimalValueAsWei() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongValue.selector, uint256(AMOUNT), AMOUNT_NATIVE));
        router.pay{value: AMOUNT}(id);
    }

    function test_pay_revertsAfterExpiry() public {
        vm.warp(1000);
        bytes32 id = _create(2000);
        vm.warp(2001);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.Expired.selector, id, uint64(2000)));
        router.pay{value: AMOUNT_NATIVE}(id);
    }

    function test_pay_succeedsAtExactExpiry() public {
        vm.warp(1000);
        bytes32 id = _create(2000);
        vm.warp(2000);
        vm.prank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);
    }

    function test_pay_revertsIfPayeeRejects() public {
        RejectingPayee bad = new RejectingPayee();
        vm.prank(address(bad));
        bytes32 id = router.createRequest(AMOUNT, 0, MEMO);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.TransferFailed.selector, address(bad), AMOUNT_NATIVE));
        router.pay{value: AMOUNT_NATIVE}(id);
    }

    // ---- cancel ----

    function test_cancel_deletesAndEmits() public {
        bytes32 id = _create(0);
        vm.expectEmit(true, false, false, false);
        emit Cancelled(id);
        vm.prank(payee);
        router.cancel(id);

        (address p,,,,,) = router.requests(id);
        assertEq(p, address(0));

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.UnknownRequest.selector, id));
        router.pay{value: AMOUNT_NATIVE}(id);
    }

    function test_cancel_revertsNotPayee() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.NotPayee.selector, payer, payee));
        router.cancel(id);
    }

    function test_cancel_revertsIfPaid() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.cancel(id);
    }

    // ---- refund ----

    function test_refund_returnsFundsAndEmits() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);

        uint256 payerBefore = payer.balance;
        vm.expectEmit(true, true, true, true);
        emit Refunded(id, payee, payer, AMOUNT);
        vm.prank(payee);
        router.refund{value: AMOUNT_NATIVE}(id);

        assertEq(payer.balance - payerBefore, AMOUNT_NATIVE);
        (address p,,,,,) = router.requests(id);
        assertEq(p, address(0));
    }

    function test_refund_revertsNotPaid() public {
        bytes32 id = _create(0);
        vm.deal(payee, AMOUNT_NATIVE);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.NotPaid.selector, id));
        router.refund{value: AMOUNT_NATIVE}(id);
    }

    function test_refund_revertsWrongValue() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        router.pay{value: AMOUNT_NATIVE}(id);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongValue.selector, AMOUNT_NATIVE - 1, AMOUNT_NATIVE));
        router.refund{value: AMOUNT_NATIVE - 1}(id);
    }

    // ---- fuzz ----

    function testFuzz_payExactAmount(uint64 amount) public {
        amount = uint64(bound(amount, 1, 1000_000000)); // up to 1000 USDC
        vm.prank(payee);
        bytes32 id = router.createRequest(amount, 0, MEMO);
        uint256 native = router.toNative(amount);
        uint256 before = payee.balance;
        vm.prank(payer);
        router.pay{value: native}(id);
        assertEq(payee.balance - before, native);
    }

    function testFuzz_payRejectsAnyOtherValue(uint64 amount, uint256 sent) public {
        amount = uint64(bound(amount, 1, 1000_000000));
        uint256 native = router.toNative(amount);
        vm.assume(sent != native && sent <= 1000 ether);
        vm.prank(payee);
        bytes32 id = router.createRequest(amount, 0, MEMO);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongValue.selector, sent, native));
        router.pay{value: sent}(id);
    }
}
