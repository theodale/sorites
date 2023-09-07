// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

/// @notice Fixed yield pool for AAVEV3.
/// @dev Utilises ERC20 LP tokens.
contract SoritesAAVEV3Pool is ERC20("SOR-AAVEV3", "Sorites AAVEV3") {
    // *** LIBRARIES ***

    using SafeERC20 for IERC20;

    // *** STATE VARIABLES ***

    // Address of AaveV3 pool
    address public immutable aavePool;

    // Address of the aToken for this pools asset on Aave
    address public immutable aToken;

    // Address of the asset this pool accepts
    address public immutable asset;

    constructor(address _aavePool, address _asset) {
        // Assign arguments to state variables
        aavePool = _aavePool;
        asset = _asset;

        // Get aToken address from Aave
        DataTypes.ReserveData memory data = IPool(_aavePool).getReserveData(_asset);
        aToken = data.aTokenAddress;
    }

    // *** LIQUIDITY PROVISION ***

    /// @notice Deposit into pool by minting an amount of shares.
    function deposit(uint256 _shares) external {
        // Get tokens owned by this pool sitting in Aave
        uint256 underlyingAssets = _underlyingAssetBalance();

        // Get total supply of shares
        uint256 totalShares = totalSupply();

        // Calculate tokens required to mint input shares
        uint256 required = (underlyingAssets * _shares) / totalShares;

        // Transfer tokens from user to this pool
        IERC20(asset).safeTransferFrom(msg.sender, address(this), required);

        // Approve tokens to Aave
        IERC20(asset).approve(aavePool, required);

        // Deposit tokens into Aave to earn yield
        IPool(aavePool).supply(asset, required, address(this), 0);
    }

    struct YieldRateCheckpoint {
        uint256 timestamp;
        uint256 yieldRate;
    }

    /// @notice Records the yield earned by the pool from its AaveV3 deposit.
    function recordYield() external view {
        // uint256 underlyingAssets = _underlyingAssetBalance();
    }

    // Get tokens owned by this pool sitting in Aave
    function _underlyingAssetBalance() internal view returns (uint256) {
        return IERC20(aToken).balanceOf(address(this));
    }
}
