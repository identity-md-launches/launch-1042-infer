// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./TestBase.sol";

/// @dev Extends the existing dependency-free test fixture without changing it.
abstract contract InferPropertyBase is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Inclusive bound that also accepts the entire uint256 domain.
    function bound(uint256 value, uint256 low, uint256 high) internal pure returns (uint256) {
        require(low <= high, "invalid test bounds");
        if (value >= low && value <= high) return value;
        uint256 width = high - low;
        if (width == type(uint256).max) return value;
        return low + value % (width + 1);
    }

    /// @dev Regularly exercise zero, one base unit and the whole available amount.
    function edgeAmount(uint256 seed, uint256 available) internal pure returns (uint256) {
        uint256 mode = seed % 4;
        if (mode == 0) return 0;
        if (mode == 1) return available == 0 ? 0 : 1;
        if (mode == 2) return available;
        return bound(seed, 0, available);
    }
}
