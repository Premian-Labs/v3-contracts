// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";
import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol"; 

import "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";


contract UnderwriterVault is IUnderwriterVault, SolidStateERC4626, OwnableInternal {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;

    address internal immutable ORACLE;

    constructor (address oracleAddress) {
        ORACLE = oracleAddress;
    }

    function setVariable(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().variable = value;
    }

    function _asset() override internal view virtual returns (address) {
        return ERC4626BaseStorage.layout().asset;
    }

    function _totalAssets() override internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalAssets;
    }

    function _totalLockedSpread() internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    /// @notice Gets the updated price per share state. Necessary for computing
    ///         the current price per share without changing variables in storage.
    function _getUpdatedPricePerShareState() internal view returns (UnderwriterVaultStorage.PricePerShareState memory)
    {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        return UnderwriterVaultStorage.PricePerShareState(
            l.totalAssets,
            l.totalLockedAssets,
            l.totalSupply,
            l.totalLockedSpread,
            l.spreadUnlockingRate
        );
    }

    function _getTotalFairValue(UnderwriterVaultStorage.PricePerShareState memory state) internal view returns (uint256) {
        // todo
        // store efficiently a list of strikes and maturities underwritten
        return 0;
    }

    function _getPricePerShare(UnderwriterVaultStorage.PricePerShareState memory state) internal view returns (uint256) {
        uint256 totalAssets = _totalAssets();
        uint256 totalSupply = _totalSupply();
        uint256 fairValue = _getTotalFairValue(state);
        uint256 totalLockedSpread = _totalLockedSpread();

        return (state.totalAssets - state.totalLockedSpread - fairValue) / state.totalSupply;
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        uint256 lastMaturity = l.lastMaturity;
        uint256 nextMaturity = l.nextMaturities[lastMaturity];
        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        uint256 totalLockedSpread = l.totalLockedSpread;

        uint256 totalAssets = _totalAssets();
        //uint256 totalLockedSpread = l.deadlineToWithdrawAmount;

        while (block.timestamp >= nextMaturity) {
            totalLockedSpread -= (nextMaturity - lastSpreadUnlockUpdate) * spreadUnlockingRate;
            spreadUnlockingRate -= l.spreadUnlockingTicks[nextMaturity];
            lastSpreadUnlockUpdate = nextMaturity;
            nextMaturity = l.nextMaturities[nextMaturity];
        }
        totalLockedSpread -= (block.timestamp - lastSpreadUnlockUpdate) * spreadUnlockingRate;
        l.totalLockedSpread = totalLockedSpread;
        l.spreadUnlockingRate = spreadUnlockingRate;
        l.lastSpreadUnlockUpdate = block.timestamp;
    }

    function _convertToShares(
        uint256 assetAmount
    ) override internal view returns (uint256 shareAmount) {

        // Get the updated state so there is no change made to storage update triggered
        UnderwriterVaultStorage.PricePerShareState memory state = _getUpdatedPricePerShareState();

        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = state.totalAssets;
            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount = assetAmount / _getPricePerShare(state);
            }
        }
    }

    function _convertToAssets(
        uint256 shareAmount
    ) override internal view virtual returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        // Get the updated state so there is no change made to storage update triggered
        UnderwriterVaultStorage.PricePerShareState memory state = _getUpdatedPricePerShareState();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = shareAmount * _getPricePerShare(state);
        }
    }

    function _maxWithdraw(
        address owner
    ) override internal view virtual returns (uint256 maxAssets) {
        UnderwriterVaultStorage.PricePerShareState memory state = _getUpdatedPricePerShareState();

        maxAssets = state.totalAssets - state.totalLockedSpread - state.totalLockedAssets;
    }

    function _maxRedeem(
        address owner
    ) override internal view virtual returns (uint256) {
        return _convertToShares(_maxWithdraw(owner)); 
    }

    function _previewDeposit(
        uint256 assetAmount
    ) override  internal view virtual returns (uint256) {
        return _convertToShares(assetAmount);
    }

    function _previewMint(
        uint256 shareAmount
    ) override internal view virtual returns (uint256) {
        return _convertToAssets(shareAmount); 
    }

    function _previewWithdraw(
        uint256 assetAmount
    ) override internal view virtual returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = _totalAssets();

            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount =
                (assetAmount * supply + totalAssets - 1) /
                totalAssets;
            }
        }
    }

    function _afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) override internal virtual {}

    function _beforeWithdraw(
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) override internal virtual {}

    function _isValidListing(uint256 strike, uint256 maturity) internal view returns (bool){
        return true;
    }

    function _handleTradeFees(uint256 premium, uint256 spread) internal view {

    }

    /// @inheritdoc IUnderwriterVault
    function buy(
        address taker,
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) override external returns (uint256 premium) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        // Validate listing
        // Check if not expired
        if (block.timestamp >= maturity)
            revert Vault__OptionExpired();

        // Check if this listing is supported by the vault. We'll need to restrict it as big moves in spot may result
        // in new listings we may want to support, making FV calculations potentially intractable.
        if (_isValidListing(strike, maturity))
            revert Vault__OptionPoolNotSupported();

        // Check if the vault has sufficient funds
        // todo: the amount of available assets can change depending on whether we introduce deadlines
        uint256 availableAssets = l.totalAssets - l.totalLockedSpread - l.totalLockedAssets;
        if (size >= availableAssets) revert Vault__InsufficientFunds();
        // Check if this listing has a pool deployed
        // revert Vault__OptionPoolNotListed();

        // Compute premium and the spread collected
        uint256 spotPrice; // get price from oracle
        uint256 timeToMaturity = maturity - block.timestamp;
        // todo: getVol should return uint
        // todo: implement batched call
        int256 sigma = IVolatilityOracle(ORACLE).getVolatility(
            _asset(),
            spotPrice,
            strike,
            timeToMaturity
        );
        uint256 volAnnualized = uint256(sigma);
        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            strike,
            timeToMaturity,
            volAnnualized,
            0,
            l.isCall
        );

        uint256 premium = size * uint256(price);
        // todo: enso / professors function call do compute the spread
        uint256 spread;
        // connect with the corresponding pool to mint shorts + longs

        // Handle the premiums and spread capture generated
        // _handleTradeFees(premium, spread)

        // below code could belong to the _handleTradeFees function
        l.totalLockedSpread += spread;
        uint256 spreadRate = spread / timeToMaturity;
        // todo: we need to update totalLockedSpread before updating the spreadUnlockingRate (!)
        // todo: otherwise there will be an inconsistency and too much spread will be deducted since lastSpreadUpdate
        // todo: call _updateState()
        l.spreadUnlockingRate += spreadRate;

        l.totalAssets += premium + spread;
        l.totalLockedAssets += size;

        return premium;
    }

    /// @inheritdoc IUnderwriterVault
    function settle() override external returns (uint256) {
        return 0;
    }

}
