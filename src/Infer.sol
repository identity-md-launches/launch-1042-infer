// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Infer (INFER)
/// @notice A fixed supply ERC-20 with 18 decimals and no administrative powers.
contract Infer is ERC20 {
    /// @notice Mints one billion tokens to the immediate deployer, including a factory.
    constructor() ERC20("Infer", "INFER") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
