// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Infer} from "../src/Infer.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./support/TestBase.sol";

/// @dev Test fixture for the immediate-deployer and CREATE2 launch behavior.
contract FactoryFixture {
    function deploy(bytes32 salt) external returns (Infer) {
        return new Infer{salt: salt}();
    }

    function move(Infer token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

contract InferTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    Infer internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Infer();
    }

    function test_MetadataAndInitialAllocation() public view {
        assertEq(token.name(), "Infer");
        assertEq(token.symbol(), "INFER");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsFullMint() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        Infer fresh = new Infer();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_FactoryReceivesEntireSupplyAndCanDistributeExactly() public {
        FactoryFixture factory = new FactoryFixture();
        Infer launched = factory.deploy(keccak256("Infer test launch"));
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        // A ten-percent distribution and claim must arrive without fees or burns.
        uint256 share = SUPPLY / 10;
        factory.move(launched, ALICE, share);
        assertEq(launched.balanceOf(ALICE), share);
        vm.prank(ALICE);
        assertTrue(launched.transfer(BOB, share));
        assertEq(launched.balanceOf(ALICE), 0);
        assertEq(launched.balanceOf(BOB), share);
        factory.move(launched, SPENDER, SUPPLY - share);
        assertEq(launched.balanceOf(SPENDER), SUPPLY - share);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 123 ether);
        assertTrue(token.transfer(ALICE, 123 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.balanceOf(ALICE), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireBalanceCanMoveAndReturn() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountSucceedsAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferWithoutBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferMaximumUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApproveEmitsEventAndCanReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalDoesNotRequireBalanceOrChangeSupply() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromConsumesAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 6 ether);
    }

    function test_TransferFromSelfConsumesAllowanceWithoutChangingBalance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteAllowanceIsNotReduced() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_TransferFromWithoutApprovalRevertsEvenForDeployer() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_AllowanceCannotBeUsedByAnotherSpender() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_InsufficientBalanceRollsBackAllowanceSpending() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 10 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 10 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromToZeroRollsBackAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderCannotMint() public {
        // Spending a zero allowance still validates its owner before the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnOrAdministrativeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        string[24] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "burn(uint256)",
            "_mint(address,uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, uint256(1));
            (bool deployerSucceeded,) = address(token).call(data);
            assertTrue(!deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(data);
            assertTrue(!strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 10 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount %= SUPPLY + 1;
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromDeliversExactAmount(uint256 approval, uint256 amount) public {
        approval %= SUPPLY + 1;
        amount %= approval + 1;
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), approval - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ExcessAllowanceSpendRevertsAtomically(uint256 approval) public {
        approval %= SUPPLY;
        assertTrue(token.approve(SPENDER, approval));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, approval, approval + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, approval + 1);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_OverdraftRevertsAtomically(uint256 balance) public {
        balance %= SUPPLY + 1;
        assertTrue(token.transfer(ALICE, balance));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, balance + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, balance + 1);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferSequencePreservesBalances(uint256 seed) public {
        address[4] memory holders = [address(this), ALICE, BOB, SPENDER];
        uint256[4] memory expected = [SUPPLY, uint256(0), uint256(0), uint256(0)];
        for (uint256 i; i < 64; ++i) {
            seed = uint256(keccak256(abi.encode(seed, i)));
            uint256 from = seed % 4;
            uint256 to = (seed >> 8) % 4;
            uint256 amount = (seed >> 16) % (expected[from] + 1);
            expected[from] -= amount;
            expected[to] += amount;
            vm.prank(holders[from]);
            assertTrue(token.transfer(holders[to], amount));
            uint256 sum;
            for (uint256 j; j < holders.length; ++j) {
                assertEq(token.balanceOf(holders[j]), expected[j]);
                sum += token.balanceOf(holders[j]);
            }
            assertEq(sum, SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }
}
