// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ArcherRouter} from "../src/ArcherRouter.sol";
import {IUSDC} from "../src/interfaces/IUSDC.sol";
import {Eip3009} from "./Eip3009.sol";

interface IUSDCDomain {
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/// Runs against the REAL Arc testnet USDC (0x3600…) on a fork. Proves the
/// EIP-712 domain, typehash, and receiveWithAuthorization semantics match what
/// the unit-test mock assumes. Skipped unless ARC_FORK=1.
///
///   ARC_FORK=1 forge test --match-contract Fork -vv
contract ArcherRouterForkTest is Test {
    address constant USDC = 0x3600000000000000000000000000000000000000;
    /// Arc-specific precompile USDC uses to move native balance (the "one
    /// pool" mechanism). Foundry cannot execute it, so tests mock it and
    /// assert on the calls USDC makes to it.
    address constant NATIVE_TRANSFER_PRECOMPILE = 0x1800000000000000000000000000000000000000;

    ArcherRouter router;
    uint256 constant PAYER_PK = 0xA11CE;
    address payer;
    address payee = makeAddr("payee");
    address relayer = makeAddr("relayer");
    uint64 constant AMOUNT = 1_500000; // 1.5 USDC

    function setUp() public {
        if (vm.envOr("ARC_FORK", uint256(0)) == 0) return;
        vm.createSelectFork("https://rpc.testnet.arc.network");
        payer = vm.addr(PAYER_PK);
        router = new ArcherRouter(IUSDC(USDC));
        // Native and ERC-20 are one pool: dealing native must show up as balanceOf.
        vm.deal(payer, 10 ether);
        vm.deal(relayer, 1 ether);
    }

    modifier onlyFork() {
        if (address(router) == address(0)) {
            emit log("skipped: set ARC_FORK=1");
            return;
        }
        _;
    }

    function test_fork_onePoolTwoViews() public onlyFork {
        assertEq(block.chainid, 5042002);
        assertEq(IUSDC(USDC).balanceOf(payer), 10_000000, "ERC-20 view must mirror native balance / 1e12");
    }

    function test_fork_payWithAuthorization_realUsdc() public onlyFork {
        vm.prank(payee);
        bytes32 id = router.createRequest(AMOUNT, 0, keccak256("fork"));

        Eip3009.Auth memory a = Eip3009.Auth({
            from: payer,
            to: address(router),
            value: AMOUNT,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: id
        });
        (uint8 v, bytes32 r, bytes32 s) = Eip3009.sign(vm, IUSDCDomain(USDC).DOMAIN_SEPARATOR(), a, PAYER_PK);

        // Real USDC verifies the signature, then moves value through the Arc
        // precompile in 18-dec native units. Mock the precompile and require
        // both legs: payer -> router, then router -> payee.
        uint256 native = router.toNative(AMOUNT);
        vm.mockCall(NATIVE_TRANSFER_PRECOMPILE, bytes(""), abi.encode(true));
        // The mock does not move funds; pre-credit the router with what leg 1
        // would deliver so USDC's balance check on leg 2 sees it.
        vm.deal(address(router), native);
        vm.expectCall(
            NATIVE_TRANSFER_PRECOMPILE,
            abi.encodeWithSignature("transfer(address,address,uint256)", payer, address(router), native)
        );
        vm.expectCall(
            NATIVE_TRANSFER_PRECOMPILE,
            abi.encodeWithSignature("transfer(address,address,uint256)", address(router), payee, native)
        );

        vm.prank(relayer);
        router.payWithAuthorization(id, payer, a.validAfter, a.validBefore, a.nonce, v, r, s);

        (,,, uint64 paidAt, address recordedPayer,) = router.requests(id);
        assertGt(paidAt, 0);
        assertEq(recordedPayer, payer);
    }

    function test_fork_replayToOtherRequest_reverts() public onlyFork {
        address attacker = makeAddr("attacker");
        vm.prank(payee);
        bytes32 victimId = router.createRequest(AMOUNT, 0, keccak256("v"));
        vm.prank(attacker);
        bytes32 attackerId = router.createRequest(AMOUNT, 0, keccak256("a"));

        Eip3009.Auth memory a = Eip3009.Auth({
            from: payer,
            to: address(router),
            value: AMOUNT,
            validAfter: 0,
            validBefore: block.timestamp + 1 hours,
            nonce: victimId
        });
        (uint8 v, bytes32 r, bytes32 s) = Eip3009.sign(vm, IUSDCDomain(USDC).DOMAIN_SEPARATOR(), a, PAYER_PK);

        // Router-level guard.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ArcherRouter.AuthorizationNonceMismatch.selector, victimId, attackerId));
        router.payWithAuthorization(attackerId, payer, a.validAfter, a.validBefore, victimId, v, r, s);

        // USDC-level guard if the attacker lies about the nonce.
        vm.prank(attacker);
        vm.expectRevert();
        router.payWithAuthorization(attackerId, payer, a.validAfter, a.validBefore, attackerId, v, r, s);

        // Bare consumption outside the router.
        vm.prank(attacker);
        vm.expectRevert();
        IUSDC(USDC)
            .receiveWithAuthorization(payer, address(router), AMOUNT, a.validAfter, a.validBefore, victimId, v, r, s);

        assertEq(IUSDC(USDC).balanceOf(attacker), 0);
    }
}
