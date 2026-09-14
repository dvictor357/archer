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
    uint96 constant AMOUNT = 25 ether; // 25 USDC (native, 18 decimals)
    bytes32 constant MEMO = keccak256("order-123");

    event RequestCreated(bytes32 indexed id, address indexed payee, uint96 amount, uint64 expiry, bytes32 memoHash);
    event Paid(bytes32 indexed id, address indexed payer, address indexed payee, uint96 amount);
    event Cancelled(bytes32 indexed id);
    event Refunded(bytes32 indexed id, address indexed payee, address indexed payer, uint96 amount);

    function setUp() public {
        router = new ArcherRouter();
        vm.deal(payer, 1000 ether);
    }

    function _create(uint64 expiry) internal returns (bytes32 id) {
        vm.prank(payee);
        id = router.createRequest(AMOUNT, expiry, MEMO);
    }

    // ---- createRequest ----

    function test_createRequest_storesAndEmits() public {
        bytes32 expectedId = router.requestId(payee, 0);
        vm.expectEmit(true, true, false, true);
        emit RequestCreated(expectedId, payee, AMOUNT, 0, MEMO);

        bytes32 id = _create(0);
        assertEq(id, expectedId);

        (address p, uint96 amt, uint64 exp, uint64 paidAt, address pr, bytes32 memo) = router.requests(id);
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
        router.pay{value: AMOUNT}(id);

        assertEq(payee.balance - before, AMOUNT);
        assertEq(address(router).balance, 0);
        (,,, uint64 paidAt, address pr,) = router.requests(id);
        assertEq(paidAt, block.timestamp);
        assertEq(pr, payer);
    }

    function test_pay_revertsUnknown() public {
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.UnknownRequest.selector, bytes32(0)));
        router.pay{value: AMOUNT}(bytes32(0));
    }

    function test_pay_revertsAlreadyPaid() public {
        bytes32 id = _create(0);
        vm.startPrank(payer);
        router.pay{value: AMOUNT}(id);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.pay{value: AMOUNT}(id);
        vm.stopPrank();
    }

    function test_pay_revertsWrongAmount() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongAmount.selector, AMOUNT - 1, AMOUNT));
        router.pay{value: AMOUNT - 1}(id);
    }

    function test_pay_revertsAfterExpiry() public {
        vm.warp(1000);
        bytes32 id = _create(2000);
        vm.warp(2001);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.Expired.selector, id, uint64(2000)));
        router.pay{value: AMOUNT}(id);
    }

    function test_pay_succeedsAtExactExpiry() public {
        vm.warp(1000);
        bytes32 id = _create(2000);
        vm.warp(2000);
        vm.prank(payer);
        router.pay{value: AMOUNT}(id);
    }

    function test_pay_revertsIfPayeeRejects() public {
        RejectingPayee bad = new RejectingPayee();
        vm.prank(address(bad));
        bytes32 id = router.createRequest(AMOUNT, 0, MEMO);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.TransferFailed.selector, address(bad), uint256(AMOUNT)));
        router.pay{value: AMOUNT}(id);
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
        router.pay{value: AMOUNT}(id);
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
        router.pay{value: AMOUNT}(id);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AlreadyPaid.selector, id));
        router.cancel(id);
    }

    // ---- refund ----

    function test_refund_returnsFundsAndEmits() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        router.pay{value: AMOUNT}(id);

        uint256 payerBefore = payer.balance;
        vm.expectEmit(true, true, true, true);
        emit Refunded(id, payee, payer, AMOUNT);
        vm.prank(payee);
        router.refund{value: AMOUNT}(id);

        assertEq(payer.balance - payerBefore, AMOUNT);
        (address p,,,,,) = router.requests(id);
        assertEq(p, address(0));
    }

    function test_refund_revertsNotPaid() public {
        bytes32 id = _create(0);
        vm.deal(payee, AMOUNT);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.NotPaid.selector, id));
        router.refund{value: AMOUNT}(id);
    }

    function test_refund_revertsWrongAmount() public {
        bytes32 id = _create(0);
        vm.prank(payer);
        router.pay{value: AMOUNT}(id);
        vm.prank(payee);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.WrongAmount.selector, AMOUNT - 1, AMOUNT));
        router.refund{value: AMOUNT - 1}(id);
    }

    // ---- fuzz ----

    function testFuzz_payExactAmount(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1000 ether));
        vm.prank(payee);
        bytes32 id = router.createRequest(amount, 0, MEMO);
        uint256 before = payee.balance;
        vm.prank(payer);
        router.pay{value: amount}(id);
        assertEq(payee.balance - before, amount);
    }
}
