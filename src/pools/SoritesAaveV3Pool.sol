// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {DataTypes} from "@aave/core-v3/contracts/protocol/libraries/types/DataTypes.sol";

// TODO:
// - Ensure historical rate period doesn't go past protocol initiation time
// - Duration doesnt have to be a uint256
// - Use NFTs
// - Take commission

/// @notice Fixed yield pool for AAVEV3
/// @dev Utilises ERC20 LP tokens
contract SoritesAAVEV3Pool is ERC721 {
    // *** LIBRARIES ***

    using SafeERC20 for IERC20;

    // *** STRUCTS ***

    // Encapsulates a fixed yield stake
    struct FixedYieldStake {
        // The principal of the stake
        uint256 principal;
        // The fixed yield promised as interest on said stake
        uint256 fixedYield;
        // The end of the stake's duration
        uint256 end;
        // The aTokens obtained from the stake's principal being deposited into Aave
        uint256 aTokens;
    }

    // *** STATE VARIABLES ***

    /// @notice Address of underlying AaveV3 pool
    IPool public immutable aavePool;

    /// @notice aToken of underlying AaveV3 pool for this pool's asset
    IERC20 public immutable aToken;

    /// @notice Address of this pool's underlying asset
    IERC20 public immutable asset;

    /// @notice ID of next stake made into the pool
    uint256 public stakeId;

    /// @notice Current reserves of the pool that can be used to top up realised yield to its nominal value
    uint256 public reserves;

    /// @notice Maps stake IDs to their state
    /// @dev Stake owners are the holders of the associated stake NFT
    mapping(uint256 => FixedYieldStake) public stakes;

    constructor(address _aavePool, address _asset, string memory _tokenName, string memory _tokenSymbol)
        ERC721(_tokenName, _tokenSymbol)
    {
        // Assign arguments to state variables
        aavePool = IPool(_aavePool);
        asset = IERC20(_asset);

        // Get aToken address from Aave
        DataTypes.ReserveData memory data = IPool(_aavePool).getReserveData(_asset);
        aToken = IERC20(data.aTokenAddress);
    }

    // *** VIEW FUNCTIONS ***

    /// @notice Calculates the yield that would be guaranteed a stake made at his moment (given sufficient reserves)
    function calculateFixedYield(uint256 _principal, uint256 _duration) public view returns (uint256) {
        return _principal * _duration * stakeId;
    }

    // *** MAKE A STAKE ***

    function deposit(uint256 _principal, uint256 _duration) external {
        uint256 fixedYield = calculateFixedYield(_principal, _duration);

        require(reserves > fixedYield, "Insufficient reserves");

        reserves -= fixedYield;

        // Transfer principal to pool
        asset.safeTransferFrom(msg.sender, address(this), _principal);

        // Cache from storage
        uint256 newStakeId = stakeId;

        uint256 initialATokenBalance = aToken.balanceOf(address(this));

        aavePool.supply(address(asset), _principal, address(this), 0);

        uint256 finalATokenBalance = aToken.balanceOf(address(this));

        // Save stake state to storage
        stakes[newStakeId] = FixedYieldStake({
            principal: _principal,
            fixedYield: fixedYield,
            end: block.timestamp + _duration,
            aTokens: finalATokenBalance - initialATokenBalance
        });

        // Mint stake NFT
        _mint(msg.sender, newStakeId);

        // Increment stake ID
        stakeId++;
    }

    // *** CLAIM STAKE ***

    /// @notice Claim the principal and yield from a fixed yield stake that has surpassed its duration
    function claim(uint256 _stakeId) external {
        FixedYieldStake memory stake = stakes[_stakeId];

        require(stake.end < block.timestamp, "Stake has not ended");
        require(ownerOf(_stakeId) == msg.sender, "StakeNFT hold only");

        uint256 initialAssetBalance = asset.balanceOf(address(this));

        // Withdraw stake's aTokens from Aave
        aavePool.withdraw(address(asset), stake.aTokens, address(this));

        uint256 finalAssetBalance = asset.balanceOf(address(this));

        uint256 available = finalAssetBalance - initialAssetBalance;
        uint256 owed = stake.principal + stake.fixedYield;

        // If excess yield => add to reserves
        if (available > owed) {
            reserves += available - owed;
        }

        // Transfer fixed yield and principal to staker
        asset.safeTransfer(msg.sender, owed);

        // Delete stake
        delete stakes[_stakeId];

        // Burn stake NFT
        _burn(_stakeId);
    }

    // Get tokens owned by this pool sitting in Aave
    function _underlyingAssetBalance() internal view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /// @notice Add tokens to the pool's reserves
    /// @notice Amount of underlying asset to add
    function addToReserves(uint256 _amount) external {
        asset.safeTransferFrom(msg.sender, address(this), _amount);
        reserves += _amount;
    }
}
