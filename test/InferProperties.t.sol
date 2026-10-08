// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Infer} from "../src/Infer.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InferPropertyBase} from "./support/InferPropertyBase.sol";

/// forge-config: default.fuzz.runs = 1000
contract InferPropertiesTest is InferPropertyBase {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    Infer internal token;

    function setUp() public {
        token = new Infer();
    }

    function test_OneBaseUnitMovesWithoutRoundingAndReturns() public {
        assertTrue(token.transfer(ALICE, 1));
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumMinusOneAllowanceIsFinite() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ExhaustedAllowanceCannotBeSpentTwice() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_UnlimitedApprovalCanBeRevokedAndReplacedWithFiniteApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertTrue(token.approve(BOB, 7));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertTrue(token.approve(SPENDER, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.allowance(address(this), SPENDER), 0);

        assertTrue(token.approve(SPENDER, 2));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 2));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.allowance(address(this), BOB), 7);
        assertEq(token.balanceOf(ALICE), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_SelfTransferCannotBypassTheBalanceCheck() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        vm.prank(ALICE);
        token.transfer(ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroAmountDoesNotBypassInvalidSpenderOrRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceSurvivesRepeatedFullSupplySpending() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        for (uint256 i; i < 2; ++i) {
            vm.prank(SPENDER);
            assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
            assertEq(token.balanceOf(address(this)), 0);
            assertEq(token.balanceOf(ALICE), SUPPLY);
            assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
            vm.prank(ALICE);
            assertTrue(token.transfer(address(this), SUPPLY));
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RoundTripRestoresTwoFundedHolders(uint256 aliceSeed, uint256 bobSeed, uint256 amountSeed) public {
        uint256 aliceBalance = bound(aliceSeed, 0, SUPPLY);
        uint256 bobBalance = bound(bobSeed, 0, SUPPLY - aliceBalance);
        uint256 amount = bound(amountSeed, 0, aliceBalance);
        assertTrue(token.transfer(ALICE, aliceBalance));
        assertTrue(token.transfer(BOB, bobBalance));
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), aliceBalance - amount);
        assertEq(token.balanceOf(BOB), bobBalance + amount);
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), aliceBalance);
        assertEq(token.balanceOf(BOB), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedSpendingEqualsSingleTransfer(
        uint256 approval,
        uint256 amountSeed,
        uint256 splitSeed
    ) public {
        Infer single = new Infer();
        uint256 amount = bound(amountSeed, 0, approval < SUPPLY ? approval : SUPPLY);
        uint256 first = bound(splitSeed, 0, amount);
        assertTrue(token.approve(SPENDER, approval));
        assertTrue(single.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, first));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount - first));
        vm.prank(SPENDER);
        assertTrue(single.transferFrom(address(this), ALICE, amount));

        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), SPENDER), single.allowance(address(this), SPENDER));
        assertEq(token.allowance(address(this), SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIsolated(uint256 first, uint256 replacement, uint256 otherApproval) public {
        assertTrue(token.approve(SPENDER, otherApproval));
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, otherApproval));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, first));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, replacement));
        assertEq(token.allowance(ALICE, SPENDER), replacement);
        assertEq(token.allowance(ALICE, BOB), otherApproval);
        assertEq(token.allowance(address(this), SPENDER), otherApproval);
        assertEq(token.allowance(SPENDER, ALICE), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedOverdraftRestoresFiniteAndInfiniteApprovals(
        uint256 balanceSeed,
        uint256 amountSeed,
        bool infinite
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approval = infinite ? type(uint256).max : amount;
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
