// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Infer} from "../src/Infer.sol";
import {InferHandler} from "./support/InferHandler.sol";
import {InferPropertyBase} from "./support/InferPropertyBase.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract InferInvariantTest is InferPropertyBase {
    Infer internal token;
    InferHandler internal handler;

    function setUp() public {
        handler = new InferHandler();
        token = handler.token();
    }

    /// @dev Foundry's invariant targeting ABI; only the handler may mutate the token.
    /// Its eight non-view functions are the entire randomized action surface.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function invariant_fixedSupplyAndAllBalancesAreAccountedFor() public view {
        uint256 total;
        for (uint256 i; i < 4; ++i) {
            total += token.balanceOf(handler.actors(i));
        }
        assertEq(total, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Infer");
        assertEq(token.symbol(), "INFER");
        assertEq(token.decimals(), 18);
    }

    function invariant_eachHolderOwnsExactlyItsNetTransfers() public view {
        for (uint256 i; i < 4; ++i) {
            address holder = handler.actors(i);
            require(token.balanceOf(holder) == handler.expectedBalance(holder), "holder accounting mismatch");
        }
    }

    function invariant_onlyApprovedSpendingChangesAllowances() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                require(
                    token.allowance(owner, spender) == handler.expectedAllowance(owner, spender),
                    "allowance accounting mismatch"
                );
            }
        }
    }
}
