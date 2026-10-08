// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Infer} from "../../src/Infer.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InferPropertyBase} from "./InferPropertyBase.sol";

/// @dev Closed set of holders: every successful transfer stays within these four actors.
/// Ghost balances and approvals come from requested operations, never token getter results.
contract InferHandler is InferPropertyBase {
    Infer public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        token = new Infer();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401)];
        require(token.totalSupply() == SUPPLY, "incorrect constructor supply");
        require(token.balanceOf(address(this)) == SUPPLY, "incorrect constructor recipient");
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < actors.length; ++i) {
            _transfer(address(this), actors[i], SUPPLY / actors.length);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), edgeAmount(amountSeed, expectedBalance[from]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 mode = amountSeed % 5;
        uint256 amount = amountSeed;
        if (mode == 0) amount = 0;
        else if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else if (mode == 3) amount = expectedBalance[owner];
        _approve(owner, _actor(spenderSeed), amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = edgeAmount(amountSeed, available);

        vm.prank(spender);
        require(token.transferFrom(owner, to, amount), "delegated transfer returned false");
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = edgeAmount(amountSeed, expectedBalance[from]);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        _transfer(from, to, amount);
        // Check the intermediate state too, so two erroneous movements cannot cancel.
        require(token.balanceOf(from) == expectedBalance[from], "outbound debit mismatch");
        require(token.balanceOf(to) == expectedBalance[to], "outbound credit mismatch");
        _transfer(to, from, amount);
        require(token.balanceOf(from) == fromBefore, "round trip changed sender balance");
        require(token.balanceOf(to) == toBefore, "round trip changed receiver balance");
    }

    function rejectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: the global invariants require complete rollback.
    }

    function rejectOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        // Includes revocation and prevents infinite approvals from making this path vacuous.
        uint256 allowed = edgeAmount(amountSeed, expectedBalance[owner]);
        _approve(owner, spender, allowed);
        uint256 amount = allowed + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectUnfundedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        // The allowance check succeeds; a later balance failure must restore that allowance.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = edgeAmount(amountSeed, expectedBalance[owner]);
        if (mode % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (mode % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amount);
        } else {
            _approve(owner, spender, amount);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        require(token.approve(spender, amount), "approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        require(token.transfer(to, amount), "transfer returned false");
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}
