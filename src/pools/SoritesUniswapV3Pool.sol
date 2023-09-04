// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

/// @notice Liquidity vault for a Uniswap V3 position.
/// @dev Utilises ERC20 LP tokens.
contract SoritesUniswapV3Pool is
    ERC20("SOR-UNIV3", "Sorites UniswapV3 Share"),
    IUniswapV3MintCallback,
    IUniswapV3SwapCallback
{
    // *** LIBRARIES ***

    using SafeERC20 for IERC20;
    using TickMath for int24;

    // *** STATE VARIABLES ***

    // Underlying Uniswap V3 pool
    IUniswapV3Pool pool;

    // Pool Tokens
    IERC20 token0;
    IERC20 token1;

    // Underlying Uniswap V3 position boundaries
    int24 lowerTick;
    int24 upperTick;

    // Protocol fee taken from yield
    uint256 feeNumerator;
    uint256 feeDenominator;

    // *** DEPOSIT ***

    function provideLiquidity(uint256 _shares) external {
        // Get underlying pool's current price and tick
        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();

        // Cache from storage
        int24 lowerTick_ = lowerTick;
        int24 upperTick_ = upperTick;

        // Get this pool's Uniswap position ID
        bytes32 positionId = keccak256(abi.encodePacked(address(this), lowerTick, upperTick));

        // Get information regarding this pool's Uniswap position
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = pool.positions(positionId);

        // Get price at this pool's position boundaries using TickMath library
        uint160 lowerSqrtRatioX96 = lowerTick.getSqrtRatioAtTick();
        uint160 upperSqrtRatioX96 = upperTick.getSqrtRatioAtTick();

        // Get token amounts this pool's liquidity represents
        (uint256 token0Liquidity, uint256 token1Liquidity) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, lowerSqrtRatioX96, upperSqrtRatioX96, liquidity);

        // Get this pool's unclaimed fees
        (uint256 token0Fees, uint256 token1Fees) = _calculateUniswapFees(tick, lowerTick_, upperTick_);

        // subtract admin fees
        token0Fees -= (token0Fees * feeNumerator) / feeDenominator;
        token1Fees -= (token1Fees * feeNumerator) / feeDenominator;

        uint256 totalSupply_ = totalSupply();

        // Calculate deposits required to provide liquditity at current price
        uint256 token0Deposit = _shares * (token0Liquidity + token0Fees) / totalSupply_;
        uint256 token1Deposit = _shares * (token0Liquidity + token0Fees) / totalSupply_;

        // transfer amounts owed to contract
        if (token0Deposit > 0) {
            token0.safeTransferFrom(msg.sender, address(this), token0Deposit);
        }
        if (token1Deposit > 0) {
            token1.safeTransferFrom(msg.sender, address(this), token1Deposit);
        }

        // Recalculate liquidity to deposit to avoid rounding issues
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, lowerSqrtRatioX96, upperSqrtRatioX96, token0Deposit, token1Deposit
        );

        // LP into Uniswap
        pool.mint(address(this), lowerTick_, upperTick_, liquidity, "");

        // Mint share tokens
        _mint(msg.sender, _shares);
    }

    // *** Uniswap Callbacks

    modifier uniswapOnly() {
        require(msg.sender == address(pool), "Uniswap Only");
        _;
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external override {
        if (amount0Owed > 0) token0.safeTransfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) token1.safeTransfer(msg.sender, amount1Owed);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        if (amount0Delta > 0) {
            token0.safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            token1.safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /// *** INTERNAL ***

    /// @return totalToken0Fees Total token0 fees owned by pool sitting in Uniswap.
    /// @return totalToken1Fees Total token1 fees owned by pool sitting in Uniswap.
    function _calculateUniswapFees(int24 tick, int24 _lowerTick, int24 _upperTick)
        internal
        view
        returns (uint256 totalToken0Fees, uint256 totalToken1Fees)
    {
        (,, uint256 feeGrowthOutsideLowerToken0, uint256 feeGrowthOutsideLowerToken1,,,,) = pool.ticks(_lowerTick);
        (,, uint256 feeGrowthOutsideUpperToken0, uint256 feeGrowthOutsideUpperToken1,,,,) = pool.ticks(_upperTick);

        uint256 feeGrowthGlobalToken0 = pool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobalToken1 = pool.feeGrowthGlobal1X128();

        // Fees below and above for each token
        // Use equations 6.17 and 6.18 in whitepaper to calculate them
        uint256 feeGrowthBelowToken0;
        uint256 feeGrowthAboveToken0;
        uint256 feeGrowthBelowToken1;
        uint256 feeGrowthAboveToken1;

        if (tick < _lowerTick) {
            feeGrowthBelowToken0 = feeGrowthGlobalToken0 - feeGrowthOutsideLowerToken0;
            feeGrowthBelowToken1 = feeGrowthGlobalToken1 - feeGrowthOutsideLowerToken1;
        } else {
            feeGrowthBelowToken0 = feeGrowthOutsideLowerToken0;
            feeGrowthBelowToken1 = feeGrowthOutsideLowerToken1;
        }

        if (tick < _upperTick) {
            feeGrowthAboveToken0 = feeGrowthOutsideUpperToken0;
            feeGrowthAboveToken1 = feeGrowthOutsideUpperToken1;
        } else {
            feeGrowthAboveToken0 = feeGrowthGlobalToken0 - feeGrowthOutsideUpperToken0;
            feeGrowthAboveToken1 = feeGrowthGlobalToken1 - feeGrowthOutsideUpperToken1;
        }

        totalToken0Fees = feeGrowthGlobalToken0 - feeGrowthBelowToken0 - feeGrowthAboveToken0;
        totalToken1Fees = feeGrowthGlobalToken1 - feeGrowthBelowToken1 - feeGrowthAboveToken1;
    }
}
