// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3MintCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
// import {IUniswapV3SwapCallback} from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

// TODO:
// - LP calc when no shares minted already
// - Slot packing for feeNumerator and Denominator
// - What are tokens owed => the collect Uniswap pool method

/// @notice Liquidity pool for a Uniswap V3 position.
/// @dev Utilises ERC20 LP tokens.
contract SoritesUniswapV3Pool is ERC20("SOR-UNIV3", "Sorites UniswapV3 Share"), IUniswapV3MintCallback {
    // *** LIBRARIES ***

    using SafeERC20 for IERC20;
    using TickMath for int24;

    // *** STATE VARIABLES ***

    // Pool admin
    address public manager;

    // Underlying Uniswap V3 pool
    IUniswapV3Pool public uniswapPool;

    // Pool Tokens
    IERC20 public token0;
    IERC20 public token1;

    // Underlying Uniswap V3 position boundaries
    int24 public lowerTick;
    int24 public upperTick;

    // Protocol fee taken from yield
    uint128 public feeNumerator;
    uint128 public feeDenominator;

    // *** MODIFIERS ***

    modifier managerOnly() {
        require(msg.sender == manager, "Manager only");
        _;
    }

    modifier uniswapOnly() {
        require(msg.sender == address(uniswapPool), "Uniswap Only");
        _;
    }

    // *** CONSTRUCTOR ***

    constructor(address _uniswapPool, address _manager) {
        // Assign arguments to state variables
        uniswapPool = IUniswapV3Pool(_uniswapPool);
        manager = _manager;

        // Get Uniswap pool tokens
        token0 = IERC20(uniswapPool.token0());
        token1 = IERC20(uniswapPool.token1());
    }

    // *** LIQUIDITY PROVISION ***

    /// @notice Deposit into pool by minting an amount of shares.
    function deposit(uint256 _shares) external {
        // Cache from storage
        int24 lowerTick_ = lowerTick;
        int24 upperTick_ = upperTick;
        IUniswapV3Pool uniswapPool_ = uniswapPool;

        // Get liquidity of pool's Uniswap position
        (uint128 liquidity,,,,) = _positionInfo(uniswapPool_);

        // Get underlying pool's current price and tick
        (uint160 sqrtPriceX96, int24 tick,,,,,) = uniswapPool.slot0();

        // Get price at this pool's position boundaries using TickMath library
        uint160 lowerSqrtRatioX96 = lowerTick.getSqrtRatioAtTick();
        uint160 upperSqrtRatioX96 = upperTick.getSqrtRatioAtTick();

        // Get token amounts this pool's liquidity represents
        (uint256 token0Liquidity, uint256 token1Liquidity) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, lowerSqrtRatioX96, upperSqrtRatioX96, liquidity);

        // Get this pool's unclaimed Uniswap fees
        (uint256 token0Fees, uint256 token1Fees) = _calculateUniswapFees(tick, lowerTick_, upperTick_, uniswapPool_);

        // Take admin fees from Uniswap yield
        token0Fees -= (token0Fees * feeNumerator) / feeDenominator;
        token1Fees -= (token1Fees * feeNumerator) / feeDenominator;

        uint256 totalSupply_ = totalSupply();

        // Calculate deposits required to provide liquditity at current price
        uint256 token0Deposit = _shares * (token0Liquidity + token0Fees) / totalSupply_;
        uint256 token1Deposit = _shares * (token0Liquidity + token0Fees) / totalSupply_;

        // Transfer required tokens to this contract
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
        uniswapPool_.mint(address(this), lowerTick_, upperTick_, liquidity, "");

        // Mint share tokens
        _mint(msg.sender, _shares);
    }

    /// @notice Withdraw liquidity from pool by burning an amount of shares.
    function withdraw(uint256 _shares) external {}

    // *** ALTER POSITION ***

    /// @notice Updates the tick boundaries of the pool's underlying Uniswap position.
    function editPosition() external managerOnly {
        // Get liquidity of pool's Uniswap position
        (uint128 liquidity,,,,) = _positionInfo(uniswapPool);

        // Cache from storage
        int24 lowerTick_ = lowerTick;
        int24 upperTick_ = upperTick;

        // Burn said liquidity to claim underlying tokens
        (uint256 token0LiquidityClaimed, uint256 token1LiquidityClaimed) =
            uniswapPool.burn(lowerTick, upperTick, liquidity);

        // Claim any unclaimed fees
        (uint256 token0FeesClaimed, uint256 token1FeesClaimed) =
            uniswapPool.collect(address(this), lowerTick_, upperTick_, type(uint128).max, type(uint128).max);
    }

    // *** COMPOUND YIELD ***

    // The fees may not be in correct proportion => you may need to swap, and you may have some left over

    /// @notice Reinvests unclaimed fees back into underlying Uniswap position.
    function compoundYield() external {}

    // *** UNISWAP CALLBACKS ***

    function uniswapV3MintCallback(uint256 _token0Amount, uint256 _token1Amount, bytes calldata)
        external
        override
        uniswapOnly
    {
        _transferTokens(_token0Amount, _token1Amount);
    }

    /// *** INTERNAL ***

    // Gets underlying position information from Uniswap pool
    function _positionInfo(IUniswapV3Pool _uniswapPool)
        internal
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        // Get this pool's position ID
        bytes32 positionId = keccak256(abi.encodePacked(address(this), lowerTick, upperTick));

        // Get position information from Uniswap pool
        (liquidity, feeGrowthInside0Last, feeGrowthInside1Last, tokensOwed0, tokensOwed1) =
            _uniswapPool.positions(positionId);
    }

    // Returns fees earned by this pool's liquidity that are sitting in Uniswap unclaimed
    function _calculateUniswapFees(int24 tick, int24 _lowerTick, int24 _upperTick, IUniswapV3Pool _uniswapPool)
        internal
        view
        returns (uint256 totalToken0Fees, uint256 totalToken1Fees)
    {
        (,, uint256 feeGrowthOutsideLowerToken0, uint256 feeGrowthOutsideLowerToken1,,,,) =
            _uniswapPool.ticks(_lowerTick);
        (,, uint256 feeGrowthOutsideUpperToken0, uint256 feeGrowthOutsideUpperToken1,,,,) =
            _uniswapPool.ticks(_upperTick);

        uint256 feeGrowthGlobalToken0 = _uniswapPool.feeGrowthGlobal0X128();
        uint256 feeGrowthGlobalToken1 = _uniswapPool.feeGrowthGlobal1X128();

        // Fees below and above for each token => calculate via whitepaper equations 6.17 and 6.18
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

    // Token transfer logic shared between Uniswap callbacks
    function _transferTokens(uint256 _token0Amount, uint256 _token1Amount) internal {
        if (_token0Amount > 0) token0.safeTransfer(msg.sender, _token0Amount);
        if (_token1Amount > 0) token0.safeTransfer(msg.sender, _token1Amount);
    }
}
