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

    uint256 internal constant SECONDSINAYEAR = 31536000;
    uint256 internal constant SECONDSINAHOUR = 3600;

    address internal immutable IV_ORACLE_ADDR;
    address internal immutable FACTORY_ADDR;

    int256 internal constant ONE = 1e18;

    struct AfterBuyArgs {
        uint256 maturity;
        uint256 premium;
        uint256 secondsToExpiration;
        uint256 size;
        uint256 spread;
        uint256 strike;
    }

    struct TradeArgs {
        uint256 strike;
        uint256 maturity;
        uint256 size;
    }

    struct UnexpiredListingVars {
        uint256[] strikes;
        uint256[] timeToMaturities;
        uint256[] maturities;
    }

    constructor(address oracleAddress, address factoryAddress) {
        IV_ORACLE_ADDR = oracleAddress;
        FACTORY_ADDR = factoryAddress;
    }

    function _totalAssets() internal view override returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalAssets;
    }

    function _totalLockedSpread() internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    function _getSpotPrice() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(UnderwriterVaultStorage.layout().oracleAdapter)
                .quote(l.base, l.quote);
    }

    function _getSpotPrice(uint256 timestamp) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(UnderwriterVaultStorage.layout().oracleAdapter)
                .quoteFrom(l.base, l.quote, timestamp);
    }

    function _getMaturityAfterTimestamp(
        uint256 timestamp
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (timestamp >= l.maxMaturity) revert Vault__GreaterThanMaxMaturity();

        uint256 current = l.minMaturity;

        while (current <= timestamp && current != 0) {
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
        uint256 timestamp
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 spot;
        uint256 strike;
        uint256 price;
        uint256 premium;
        uint256 size;

        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;
        uint256 total = 0;

        while (current <= timestamp && current != 0) {
            spot = _getSpotPrice(current);

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
                    0,
                    l.isCall
                );

                size = l.positionSizes[current][strike];
                premium = l.isCall ? price.div(spot) : price;
                total += premium.mul(size);
            }

            current = l.maturities.next(current);
        }

        return total;
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

        if (l.maxMaturity <= timestamp) return 0;

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

        for (uint256 x = 0; x < n; x++) {
            price = OptionMath.blackScholesPrice(
                spot,
                listings.strikes[x],
                listings.timeToMaturities[x],
                uint256(sigmas[x]),
                0,
                l.isCall
            );

            size = l.positionSizes[listings.maturities[x]][listings.strikes[x]];
            total += price.mul(size);
        }

        return l.isCall ? total.div(spot) : total;
    }

    function _getTotalFairValue() internal view returns (uint256) {
        uint256 spot = _getSpotPrice();
        uint256 timestamp = block.timestamp;
        return
            _getTotalFairValueUnexpired(timestamp, spot) +
            _getTotalFairValueExpired(timestamp);
    }

    function _getTotalLockedSpread() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity <= l.lastSpreadUnlockUpdate) return 0;

        uint256 current = _getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        // TODO: double check handling of negative total locked spread
        uint256 totalLockedSpread = l.totalLockedSpread;

        while (current <= block.timestamp && current != 0) {
            totalLockedSpread -=
                (current - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;

            spreadUnlockingRate -= l.spreadUnlockingTicks[current];
            lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
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

    function _contains(
        uint256 strike,
        uint256 maturity
    ) internal view returns (bool) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (!l.maturities.contains(maturity)) return false;

        return l.maturityToStrikes[maturity].contains(strike);
    }

    function _addListing(uint256 strike, uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (maturity <= block.timestamp) revert Vault__OptionExpired();

        // Insert maturity if it doesn't exist
        if (!l.maturities.contains(maturity)) {
            if (maturity < l.minMaturity) {
                l.maturities.insertBefore(l.minMaturity, maturity);
                l.minMaturity = maturity;
            } else if (
                (l.minMaturity < maturity) && (maturity) < l.maxMaturity
            ) {
                uint256 next = _getMaturityAfterTimestamp(maturity);
                l.maturities.insertBefore(next, maturity);
            } else {
                l.maturities.insertAfter(l.maxMaturity, maturity);

                if (l.minMaturity == 0) l.minMaturity = maturity;

                l.maxMaturity = maturity;
            }
        }

        // Insert strike into the set of strikes for given maturity
        if (!l.maturityToStrikes[maturity].contains(strike))
            l.maturityToStrikes[maturity].add(strike);
    }

    function _removeListing(uint256 strike, uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (_contains(strike, maturity)) {
            l.maturityToStrikes[maturity].remove(strike);

            // Remove maturity if there are no strikes left
            if (l.maturityToStrikes[maturity].length() == 0) {
                if (maturity == l.minMaturity)
                    l.minMaturity = l.maturities.next(maturity);
                if (maturity == l.maxMaturity)
                    l.maxMaturity = l.maturities.prev(maturity);

                l.maturities.remove(maturity);
            }
        }
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // TODO: double check that l.maxMaturity is updated correctly during processing of a trade
        if (l.maxMaturity > l.lastSpreadUnlockUpdate) {
            uint256 current = _getMaturityAfterTimestamp(
                l.lastSpreadUnlockUpdate
            );

            uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
            uint256 spreadUnlockingRate = l.spreadUnlockingRate;
            uint256 totalLockedSpread = l.totalLockedSpread;

            while (current <= block.timestamp && current != 0) {
                totalLockedSpread -=
                    (current - lastSpreadUnlockUpdate) *
                    spreadUnlockingRate;

                spreadUnlockingRate -= l.spreadUnlockingTicks[current];
                lastSpreadUnlockUpdate = current;
                current = l.maturities.next(current);
            }
            totalLockedSpread -=
                (block.timestamp - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;

            l.totalLockedSpread = totalLockedSpread;
            l.spreadUnlockingRate = spreadUnlockingRate;
            l.lastSpreadUnlockUpdate = block.timestamp;
        }
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
        uint256 sigma,
        uint256 rfRate
    ) internal view returns (address) {
        uint256 dte = tau.mul(365e18);

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
            rfRate,
            l.isCall
        );
        if (delta < l.minDelta || delta > l.maxDelta)
            revert Vault__DeltaBounds();

        // NOTE: query returns address(0) if no listing exists
        address listingAddr = _getFactoryAddress(strike, maturity);

        return listingAddr;
    }

    function _afterBuy(AfterBuyArgs memory a) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        _updateState();
        uint256 spreadRate = a.spread / a.secondsToExpiration;
        uint256 newLockedAssets = l.isCall ? a.size : a.size.mul(a.strike);

        l.spreadUnlockingRate += spreadRate;
        l.spreadUnlockingTicks[a.maturity] += spreadRate;
        l.totalLockedSpread += a.spread;
        l.totalAssets += a.premium + a.spread;
        l.totalLockedAssets += newLockedAssets;
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
        if (listingAddr == address(0)) revert Vault__OptionPoolNotListed();
        return listingAddr;
    }

    // Utilization rate will be vol global for entire surface
    function _getCLevel(uint256 collateralAmt) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxCLevel == 0) revert Vault__CLevelBounds();
        if (l.alphaCLevel == 0) revert Vault__CLevelBounds();

        uint256 postUtilisation = (l.totalLockedAssets + collateralAmt).div(
            l.totalAssets
        );

        if (postUtilisation > ONE.toUint256()) revert Vault__UtilEstError();

        uint256 hoursSinceLastTx = (block.timestamp - l.lastTradeTimestamp).div(
            SECONDSINAHOUR
        );

        uint256 cLevel = _calculateCLevel(
            postUtilisation,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel
        );
        if (cLevel < l.minCLevel) revert Vault__lowCLevel();

        uint256 discount = l.hourlyDecayDiscount.mul(hoursSinceLastTx);

        if (cLevel - discount < l.minCLevel) return l.minCLevel;

        return cLevel - discount;
    }

    // https://www.desmos.com/calculator/0uzv50t7jy
    function _calculateCLevel(
        uint256 postUtilisation,
        uint256 alphaCLevel,
        uint256 minCLevel,
        uint256 maxCLevel
    ) internal pure returns (uint256) {
        int256 freeCapitalRatio = ONE - postUtilisation.toInt256();
        int256 positiveExp = alphaCLevel.toInt256().mul(freeCapitalRatio).exp();
        int256 alphaCLevelExp = alphaCLevel.exp().toInt256();
        int256 k = alphaCLevel
            .toInt256()
            .mul(
                minCLevel.toInt256().mul(alphaCLevelExp - maxCLevel.toInt256())
            )
            .div(alphaCLevelExp - ONE);
        return
            (k.mul(positiveExp) + maxCLevel.mul(alphaCLevel).toInt256() - k)
                .div(alphaCLevel.toInt256().mul(positiveExp))
                .toUint256();
    }

    function _quote(
        TradeArgs memory args
    ) internal view returns (address, uint256, uint256, uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 collateralAmt = l.isCall
            ? args.size
            : args.size.mul(args.strike);

        // Check non Zero Strike
        if (args.strike == 0) revert Vault__StrikeZero();
        // Check valid maturity
        if (block.timestamp >= args.maturity) revert Vault__OptionExpired();
        // Compute premium and the spread collected
        uint256 spotPrice = _getSpotPrice();

        uint256 tau = (args.maturity - block.timestamp).div(SECONDSINAYEAR);

        int256 sigma = IVolatilityOracle(IV_ORACLE_ADDR).getVolatility(
            _asset(),
            spotPrice,
            args.strike,
            tau
        );

        uint256 rfRate = IVolatilityOracle(IV_ORACLE_ADDR).getrfRate();

        address poolAddr = _isValidListing(
            spotPrice,
            args.strike,
            args.maturity,
            tau,
            uint256(sigma),
            rfRate
        );

        // returns USD price for calls & puts
        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            args.strike,
            tau,
            uint256(sigma),
            rfRate,
            l.isCall
        );

        if (l.isCall) price = price.div(spotPrice);

        // call denominated in base, put denominated in quote
        uint256 mintingFee = IPool(poolAddr).takerFee(args.size, 0, false);

        // Check if the vault has sufficient funds
        if ((collateralAmt + mintingFee) >= _availableAssets())
            revert Vault__InsufficientFunds();

        return (poolAddr, price, mintingFee, _getCLevel(collateralAmt));
    }

    function _buy(TradeArgs memory args) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Get pool address, price and c-level
        (
            address poolAddr,
            uint256 price,
            uint256 mintingFee,
            uint256 cLevel
        ) = _quote(args);

        // Add listing
        _addListing(args.strike, args.maturity);

        uint256 totalSpread = (cLevel - l.minCLevel).mul(price).mul(args.size) +
            mintingFee;

        // Approve transfer of base / quote token
        IERC20(_asset()).approve(poolAddr, args.size + mintingFee);

        // Mint option and allocate long token
        IPool(poolAddr).writeFrom(address(this), msg.sender, args.size);

        uint256 secondsToExpiration = args.maturity - block.timestamp;

        // Handle the premiums and spread capture generated
        AfterBuyArgs memory intel = AfterBuyArgs(
            args.maturity,
            args.size * price,
            secondsToExpiration,
            args.size,
            totalSpread,
            args.strike
        );
        _afterBuy(intel);
    }

    /// @inheritdoc IUnderwriterVault
    function buy(uint256 strike, uint256 maturity, uint256 size) external {
        TradeArgs memory args;
        args.strike = strike;
        args.maturity = maturity;
        args.size = size;
        return _buy(args);
    }

    /// @inheritdoc IUnderwriterVault
    function quote(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external view returns (address, uint256, uint256, uint256) {
        TradeArgs memory args;
        args.strike = strike;
        args.maturity = maturity;
        args.size = size;
        return _quote(args);
    }

    function _settleMaturity(uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 unlockedCollateral;
        uint256 exerciseValue;
        uint256 settlementValue;
        uint256 positionSize;
        uint256 strike;

        address listingAddr;

        for (uint256 i = 0; i < l.maturityToStrikes[maturity].length(); i++) {
            strike = l.maturityToStrikes[maturity].at(i);
            positionSize = l.positionSizes[maturity][strike];
            unlockedCollateral = l.isCall
                ? positionSize
                : positionSize.mul(strike);
            l.totalLockedAssets -= unlockedCollateral;
            listingAddr = _getFactoryAddress(strike, maturity);
            settlementValue = IPool(listingAddr).settle(address(this));
            exerciseValue = unlockedCollateral - settlementValue;
            l.totalAssets -= exerciseValue;
        }
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external override returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // Get last maturity that is greater than the current time
        uint256 lastExpired;

        if (block.timestamp >= l.maxMaturity) {
            lastExpired = l.maxMaturity;
        } else {
            lastExpired = _getMaturityAfterTimestamp(block.timestamp);
            lastExpired = l.maturities.prev(lastExpired);
        }

        uint256 current = l.minMaturity;
        uint256 next;
        uint256 numStrikes;

        while (current <= lastExpired && current != 0) {
            _settleMaturity(current);

            // Remove maturity from data structure
            next = l.maturities.next(current);
            numStrikes = l.maturityToStrikes[current].length();
            for (uint256 i = 0; i < numStrikes; i++) {
                l.positionSizes[current][
                    l.maturityToStrikes[current].at(0)
                ] = 0;
                _removeListing(l.maturityToStrikes[current].at(0), current);
            }
            current = next;
        }

        return 0;
    }
}
