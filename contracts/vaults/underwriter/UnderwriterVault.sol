// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";
import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

import "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/volatility/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {IPoolFactory} from "../../factory/IPoolFactory.sol";
import {IPool} from "../../pool/IPool.sol";
import {IOracleAdapter} from "../../oracle/price/IOracleAdapter.sol";

import "hardhat/console.sol";
import {UD60x18} from "../../libraries/prbMath/UD60x18.sol";
import {SD59x18} from "../../libraries/prbMath/SD59x18.sol";

contract UnderwriterVault is
    IUnderwriterVault,
    SolidStateERC4626,
    OwnableInternal
{
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSet for EnumerableSet.UintSet;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;
    using UD60x18 for uint256;
    using SD59x18 for int256;

    uint256 SECONDSINAYEAR = 365 * 24 * 60 * 60;
    uint256 SECONDSINAHOUR = 60 * 60;

    address internal immutable IV_ORACLE_ADDR;
    address internal immutable FACTORY_ADDR;

    struct afterBuyStruct {
        uint256 maturity;
        uint256 premium;
        uint256 secondsToExpiration;
        uint256 size;
        uint256 spread;
        uint256 strike;
    }

    struct UnexpiredListingVars {
        uint256[] strikes;
        uint256[] timeToMaturities;
        uint256[] maturities;
    }

    struct TradeParams {
        uint256 strike;
        uint256 maturity;
        uint256 size;
    }

    constructor(address oracleAddress, address factoryAddress) {
        IV_ORACLE_ADDR = oracleAddress;
        FACTORY_ADDR = factoryAddress;
    }

    function _asset() internal view virtual override returns (address) {
        return ERC4626BaseStorage.layout().asset;
    }

    function _totalAssets() internal view override returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalAssets;
    }

    function _totalLockedSpread() internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    function _getSpotPrice(
        address oracleAdapterAddr
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // TODO
        /* uint256 price = IOracleAdapter(oracleAdapterAddr).quote(
            l.base,
            l.quote
        );
        */
        uint256 price = 1000000000000000000;
        return price;
    }

    function _getMaturityAfterTimestamp(
        uint256 timestamp
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (timestamp > l.maxMaturity) revert Vault__GreaterThanMaxMaturity();

        uint256 current = l.minMaturity;

        while (current <= timestamp) {
            if (l.maturities.next(current) < current)
                revert Vault__NonMonotonicMaturities();
            current = l.maturities.next(current);
        }
        return current;
    }

    function _getNumberOfUnexpiredListings(
        uint256 timestamp
    ) internal view returns (uint256) {
        uint256 n = 0;
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity <= timestamp) return 0;

        uint256 current = _getMaturityAfterTimestamp(timestamp);

        while (current <= l.maxMaturity && current != 0) {
            n += l.maturityToStrikes[current].length();
            current = l.maturities.next(current);
        }

        return n;
    }

    function _getTotalFairValueExpired(
        uint256 timestamp,
        uint256 spot
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        //uint256 spot = _getSpotPrice(l.oracleAdapter);
        uint256 strike;
        uint256 price;
        uint256 size;

        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;
        uint256 total = 0;

        while (current <= timestamp && current != 0) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                strike = l.maturityToStrikes[current].at(i);

                price = OptionMath.blackScholesPrice(
                    spot,
                    strike,
                    0,
                    1,
                    l.rfRate,
                    l.isCall
                );

                size = l.positionSizes[current][strike];
                total += price.mul(size);
            }

            current = l.maturities.next(current);
        }

        return l.isCall ? total.div(spot) : total;
    }

    function _getTotalFairValueUnexpired(
        uint256 timestamp,
        uint256 spot
    ) internal view returns (uint256) {
        uint256 price;
        uint256 size;
        uint256 timeToMaturity;

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity < timestamp) return 0;

        uint256 current = _getMaturityAfterTimestamp(timestamp);
        uint256 total = 0;

        // Compute fair value for options that have not expired
        uint256 n = _getNumberOfUnexpiredListings(timestamp);

        UnexpiredListingVars memory listings = UnexpiredListingVars({
            strikes: new uint256[](n),
            timeToMaturities: new uint256[](n),
            maturities: new uint256[](n)
        });

        uint256 i = 0;
        while (current <= l.maxMaturity && current != 0) {
            timeToMaturity = (current - timestamp).div(365 * 24 * 60 * 60);

            for (
                uint256 j = 0;
                j < l.maturityToStrikes[current].length();
                j++
            ) {
                listings.strikes[i] = l.maturityToStrikes[current].at(j);
                listings.timeToMaturities[i] = timeToMaturity;
                listings.maturities[i] = current;

                i++;
            }

            current = l.maturities.next(current);
        }

        int256[] memory sigmas = IVolatilityOracle(IV_ORACLE_ADDR)
            .getVolatility(
                _asset(),
                spot,
                listings.strikes,
                listings.timeToMaturities
            );

        for (uint256 i = 0; i < n; i++) {
            price = OptionMath.blackScholesPrice(
                spot,
                listings.strikes[i],
                listings.timeToMaturities[i],
                uint256(sigmas[i]),
                0,
                l.isCall
            );

            size = l.positionSizes[listings.maturities[i]][listings.strikes[i]];
            total += price.mul(size);
        }

        return l.isCall ? total.div(spot) : total;
    }

    function _getTotalFairValue() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 spot = _getSpotPrice(l.oracleAdapter);
        uint256 timestamp = block.timestamp;
        return
            _getTotalFairValueUnexpired(timestamp, spot) +
            _getTotalFairValueExpired(timestamp, spot);
    }

    function _getTotalLockedSpread() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 current = _getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);
        uint256 next;

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        // TODO: double check handling of negative total locked spread
        uint256 totalLockedSpread = l.totalLockedSpread;

        while (current <= block.timestamp) {
            totalLockedSpread -=
                (current - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;

            spreadUnlockingRate -= l.spreadUnlockingTicks[current];
            lastSpreadUnlockUpdate = current;
            next = l.maturities.next(current);
            if (next < current) revert Vault__NonMonotonicMaturities();
            current = next;
        }
        totalLockedSpread -=
            (block.timestamp - lastSpreadUnlockUpdate) *
            spreadUnlockingRate;
        return totalLockedSpread;
    }

    function _availableAssets() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.totalAssets - _getTotalLockedSpread() - l.totalLockedAssets;
    }

    function _getPricePerShare() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        return
            (l.totalAssets - _getTotalLockedSpread() - _getTotalFairValue())
                .div(_totalSupply());
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = _getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);
        uint256 next;

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        uint256 totalLockedSpread = l.totalLockedSpread;

        while (current <= block.timestamp) {
            totalLockedSpread -=
                (current - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;

            spreadUnlockingRate -= l.spreadUnlockingTicks[current];
            lastSpreadUnlockUpdate = current;
            next = l.maturities.next(current);
            if (next < current) revert Vault__NonMonotonicMaturities();
            current = next;
        }
        totalLockedSpread -=
            (block.timestamp - lastSpreadUnlockUpdate) *
            spreadUnlockingRate;

        l.totalLockedSpread = totalLockedSpread;
        l.spreadUnlockingRate = spreadUnlockingRate;
        l.lastSpreadUnlockUpdate = block.timestamp;
    }

    function _convertToShares(
        uint256 assetAmount
    ) internal view override returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = _totalAssets();
            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount = assetAmount.div(_getPricePerShare());
            }
        }
    }

    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            revert Vault__ZEROShares();
        } else {
            assetAmount = shareAmount.mul(_getPricePerShare());
        }
    }

    function _maxWithdraw(
        address owner
    ) internal view virtual override returns (uint256 withdrawableAssets) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }

        uint256 assetsOwner = _convertToAssets(_balanceOf(owner));
        uint256 availableAssets = _availableAssets();

        if (assetsOwner >= availableAssets) {
            withdrawableAssets = availableAssets;
        } else {
            withdrawableAssets = assetsOwner;
        }
    }

    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        return _convertToShares(_maxWithdraw(owner));
    }

    function _previewMint(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = shareAmount.mul(_getPricePerShare());
        }
    }

    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            revert Vault__ZEROShares();
        } else {
            uint256 totalAssets = _totalAssets();

            if (totalAssets == 0) {
                revert Vault__InsufficientFunds();
            } else {
                shareAmount = assetAmount.div(_getPricePerShare());
            }
        }
    }

    function _afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual override {
        if (receiver == address(0)) {
            revert Vault__AddressZero();
        }
        if (assetAmount == 0) {
            revert Vault__ZeroAsset();
        }
        if (shareAmount == 0) {
            revert Vault__ZEROShares();
        }
        UnderwriterVaultStorage.layout().totalAssets += assetAmount;
    }

    function _beforeWithdraw(
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual override {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }
        if (assetAmount == 0) {
            revert Vault__ZeroAsset();
        }
        if (shareAmount == 0) {
            revert Vault__ZEROShares();
        }
    }

    function _isValidListing(
        uint256 spotPrice,
        uint256 strike,
        uint256 maturity,
        uint256 tau,
        uint256 sigma
    ) internal view returns (address) {
        uint256 dte = tau.mul(365);
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // DTE filter
        if (dte > l.maxDTE || dte < l.minDTE) revert Vault__MaturityBounds();

        // Delta filter
        int256 delta = OptionMath.optionDelta(
            spotPrice,
            strike,
            tau,
            sigma,
            l.rfRate,
            l.isCall
        );
        if (delta < l.minDelta || delta > l.maxDelta)
            revert Vault__DeltaBounds();

        // NOTE: query returns address(0) if no listing exists
        address listingAddr = _getFactoryAddress(strike, maturity);
        if (listingAddr == address(0)) revert Vault__OptionPoolNotListed();

        return listingAddr;
    }

    function _addListing(uint256 strike, uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Insert maturity if it doesn't exist
        if (!l.maturities.contains(maturity)) {
            uint256 before = l.maturities.prev(maturity);
            l.maturities.insertAfter(before, maturity);
        }

        // Insert strike into the set of strikes for given maturity
        l.maturityToStrikes[maturity].add(strike);

        // Set new max maturity for doublylinkedlist
        if (maturity > l.maxMaturity) {
            l.maxMaturity = maturity;
        }
    }

    function _afterBuy(afterBuyStruct memory a) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        _updateState();
        uint256 spreadRate = a.spread / a.secondsToExpiration;

        l.spreadUnlockingRate += spreadRate;
        l.spreadUnlockingTicks[a.maturity] += spreadRate;
        l.totalLockedSpread += a.spread;
        l.totalAssets += a.premium + a.spread;
        l.totalLockedAssets += a.size;
        l.positionSizes[a.maturity][a.strike] += a.size;
        l.lastTradeTimestamp = block.timestamp;
    }

    function _getFactoryAddress(
        uint256 strike,
        uint256 maturity
    ) internal view returns (address) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // generate struct to grab pool address
        IPoolFactory.PoolKey memory _poolKey;
        _poolKey.base = l.base;
        _poolKey.quote = l.quote;
        _poolKey.oracleAdapter = l.oracleAdapter;
        _poolKey.strike = strike;
        _poolKey.maturity = uint64(maturity);
        _poolKey.isCallPool = l.isCall;

        address listingAddr = IPoolFactory(FACTORY_ADDR).getPoolAddress(
            _poolKey
        );

        return listingAddr;
    }

    // Utilization rate will be vol global for entire surface
    function _getClevel(uint256 collateralAmt) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxClevel == 0) revert Vault__CLevelBounds();
        if (l.alphaClevel == 0) revert Vault__CLevelBounds();

        uint256 postUtilisation = (l.totalLockedAssets + collateralAmt).div(
            l.totalAssets
        );

        if (postUtilisation > 1) revert Vault__UtilEstError();

        uint256 hoursSinceLastTx = (block.timestamp - l.lastTradeTimestamp).div(
            SECONDSINAHOUR
        );

        uint256 cLevel = _calculateClevel(
            postUtilisation,
            l.alphaClevel,
            l.minClevel,
            l.maxClevel
        );

        uint256 discount = l.hourlyDecayDiscount * hoursSinceLastTx;

        if (cLevel - discount < l.minClevel) return l.minClevel;

        return cLevel - discount;
    }

    //  Calculate the price of an option using the Black-Scholes model
    function _calculateClevel(
        uint256 postUtilisation,
        uint256 alphaClevel,
        uint256 minClevel,
        uint256 maxClevel
    ) internal pure returns (uint256) {
        uint256 k = alphaClevel * minClevel;
        uint256 positiveExp = (alphaClevel * postUtilisation).exp();
        uint256 negativeExp = (-alphaClevel.toInt256() *
            postUtilisation.toInt256()).exp().toUint256();
        return
            (negativeExp * (k * positiveExp + maxClevel * alphaClevel - k)).div(
                alphaClevel
            );
    }

    function _quote(
        TradeParams memory params
    ) internal view returns (address, uint256, uint256, uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 collateralAmt = l.isCall
            ? params.size
            : params.size.mul(params.strike);

        // Check non Zero Strike
        if (params.strike == 0) revert Vault__AddressZero();
        // Check valid maturity
        if (block.timestamp >= params.maturity) revert Vault__OptionExpired();
        // Compute premium and the spread collected
        uint256 spotPrice = _getSpotPrice(l.oracleAdapter);

        uint256 tau = (params.maturity - block.timestamp).div(SECONDSINAYEAR);

        int256 sigma = IVolatilityOracle(IV_ORACLE_ADDR).getVolatility(
            _asset(),
            spotPrice,
            params.strike,
            tau
        );

        address poolAddr = _isValidListing(
            spotPrice,
            params.strike,
            params.maturity,
            tau,
            uint256(sigma)
        );

        // returns USD price for calls & puts
        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            params.strike,
            tau,
            uint256(sigma),
            l.rfRate,
            l.isCall
        );

        if (l.isCall) price = price.div(spotPrice);

        // call denominated in base, put denominated in quote
        uint256 mintingFee = IPool(poolAddr).takerFee(params.size, 0, false);
        // Check if the vault has sufficient funds
        if ((collateralAmt + mintingFee) >= _availableAssets())
            revert Vault__InsufficientFunds();

        return (poolAddr, price, mintingFee, _getClevel(collateralAmt));
    }

    function _buy(TradeParams memory params) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Get pool address, price and c-level
        (
            address poolAddr,
            uint256 price,
            uint256 mintingFee,
            uint256 cLevel
        ) = _quote(params);

        // Add listing
        _addListing(params.strike, params.maturity);

        uint256 totalSpread = (cLevel - l.minClevel).mul(price).mul(
            params.size
        ) + mintingFee;

        // Mint option and allocate long token
        IPool(poolAddr).writeFrom(address(this), msg.sender, params.size);

        uint256 secondsToExpiration = params.maturity - block.timestamp;
        // Handle the premiums and spread capture generated
        afterBuyStruct memory intel = afterBuyStruct(
            params.maturity,
            params.size * price,
            secondsToExpiration,
            params.size,
            totalSpread,
            params.strike
        );

        _afterBuy(intel);
    }

    /// @inheritdoc IUnderwriterVault
    function buy(uint256 strike, uint256 maturity, uint256 size) external {
        TradeParams memory params;
        params.strike = strike;
        params.maturity = maturity;
        params.size = size;
        return _buy(params);
    }

    /// @inheritdoc IUnderwriterVault
    function quote(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external view returns (address, uint256, uint256, uint256) {
        TradeParams memory params;
        params.strike = strike;
        params.maturity = maturity;
        params.size = size;
        return _quote(params);
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external pure override returns (uint256) {
        //TODO: remove pure when hydrated
        return 0;
    }
}
