// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Fixed yield pool for AAVEV3.
/// @dev Utilises ERC20 LP tokens.
contract SoritesAAVEV3Pool is ERC20("SOR-AAVEV3", "Sorites AAVEV3") {
    // *** LIBRARIES ***

    using SafeERC20 for IERC20;

    // *** LIQUIDITY PROVISION ***

    /// @notice Deposit into pool by minting an amount of shares.
    function deposit(uint256 _shares) external {}
}
