// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SolidStateERC4626} from "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {ERC4626BaseInternal} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

import {IUnderwriterVault} from "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/volatility/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {IPoolFactory} from "../../factory/IPoolFactory.sol";
import {IPool} from "../../pool/IPool.sol";
import {IOracleAdapter} from "../../oracle/price/IOracleAdapter.sol";

import {UD60x18} from "../../libraries/prbMath/UD60x18.sol";
import {SD59x18} from "../../libraries/prbMath/SD59x18.sol";

/// @title An ERC-4626 implementation for underwriting call/put option
///        contracts by using collateral deposited by users
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

    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant ONE_HOUR = 1 hours;

    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;

    int256 internal constant ONE = 1e18;

    // The structs below are used as a way to reduce stack depth and avoid "stack too deep" errors
    struct AfterBuyArgs {
        // The maturity of a listing
        uint256 maturity;
        // The vanilla Black-Scholes premium paid by the option buyer
        uint256 premium;
        // The time until maturity (seconds) for the listing
        uint256 secondsToExpiration;
        // The number of contracts for an option purchase
        uint256 size;
        // The spread captured from selling an option
        uint256 spread;
        // The strike of a listing
        uint256 strike;
    }

    struct BlackScholesArgs {
        // The spot price
        uint256 spot;
        // The strike price of the listing
        uint256 strike;
        // The time until maturity (years)
        uint256 timeToMaturity;
        // The implied volatility for the listing
        uint256 volAnnualized;
        // The risk-free rate
        uint256 riskFreeRate;
        // Whether the option is a buy or a sell
        bool isCall;
    }

    struct TradeArgs {
        // The strike price of the listing
        uint256 strike;
        // The maturity of the listing
        uint256 maturity;
        // The number of contracts being traded
        uint256 size;
    }

    struct UnexpiredListingVars {
        // A list of strikes for a set of listings
        uint256[] strikes;
        // A list of time until maturity (years) for a set of listings
        uint256[] timeToMaturities;
        // A list of maturities for a set of listings
        uint256[] maturities;
    }

    /// @notice The constructor for this vault
    /// @param oracleAddress The address for the volatility oracle
    /// @param factoryAddress The pool factory address
    constructor(address oracleAddress, address factoryAddress) {
        IV_ORACLE = oracleAddress;
        FACTORY = factoryAddress;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view override returns (uint256) {
        // total assets = deposits + premiums + spreads
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return IERC20(_asset()).balanceOf(address(this)) + l.totalLockedAssets;
    }

    /// @notice Gets the total locked spread currently stored in storage
    /// @return The total locked spread in stored in storage
    function _totalLockedSpread() internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    /// @notice Gets the spot price at the current time
    /// @return The spot price at the current time
    function _getSpotPrice() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(UnderwriterVaultStorage.layout().oracleAdapter)
                .quote(l.base, l.quote);
    }

    /// @notice Gets the spot price at the given timestamp
    /// @param timestamp The given timestamp
    /// @return The spot price at the given timestamp
    function _getSpotPrice(uint256 timestamp) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(UnderwriterVaultStorage.layout().oracleAdapter)
                .quoteFrom(l.base, l.quote, timestamp);
    }

    /// @notice Gets the nearest maturity after the given timestamp, exclusive
    ///         of the timestamp being on a maturity
    /// @param timestamp The given timestamp
    /// @return The nearest maturity after the given timestamp
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

    /// @notice Gets the number of unexpired listings within the basket of
    ///         options underwritten by this vault at the current time
    /// @param timestamp The given timestamp
    /// @return The number of unexpired listings
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

    /// @notice Gets the total fair value of the basket of expired options underwritten
    ///         by this vault at the current time
    /// @param timestamp The given timestamp
    /// @return The total fair value of the basket of expired options underwritten
    function _getTotalFairValueExpired(
        uint256 timestamp
    ) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;
        uint256 total = 0;

        while (current <= timestamp && current != 0) {
            uint256 spot = _getSpotPrice(current);

            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                uint256 strike = l.maturityToStrikes[current].at(i);

                uint256 price = OptionMath.blackScholesPrice(
                    spot,
                    strike,
                    0,
                    1,
                    0,
                    l.isCall
                );

                uint256 size = l.positionSizes[current][strike];
                uint256 premium = l.isCall ? price.div(spot) : price;
                total += premium.mul(size);
            }

            current = l.maturities.next(current);
        }

        return total;
    }

    /// @notice Gets the total fair value of the basket of unexpired options underwritten
    ///         by this vault at the current time
    /// @param timestamp The given timestamp
    /// @param spot The spot price
    /// @return The total fair value of the basket of unexpired options underwritten
    function _getTotalFairValueUnexpired(
        uint256 timestamp,
        uint256 spot
    ) internal view returns (uint256) {
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
            uint256 timeToMaturity = (current - timestamp).div(
                365 * 24 * 60 * 60
            );

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

        uint256[] memory sigmas = IVolatilityOracle(IV_ORACLE).getVolatility(
            _asset(),
            spot,
            listings.strikes,
            listings.timeToMaturities
        );

        for (uint256 x = 0; x < n; x++) {
            uint256 price = OptionMath.blackScholesPrice(
                spot,
                listings.strikes[x],
                listings.timeToMaturities[x],
                sigmas[x],
                0,
                l.isCall
            );

            uint256 size = l.positionSizes[listings.maturities[x]][
                listings.strikes[x]
            ];
            total += price.mul(size);
        }

        return l.isCall ? total.div(spot) : total;
    }

    /// @notice Gets the total fair value of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total fair value of the basket of options underwritten
    function _getTotalFairValue() internal view returns (uint256) {
        uint256 spot = _getSpotPrice();
        uint256 timestamp = block.timestamp;
        return
            _getTotalFairValueUnexpired(timestamp, spot) +
            _getTotalFairValueExpired(timestamp);
    }

    /// @notice Gets the total locked spread for the vault
    /// @return The total locked spread
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

    /// @notice Gets the current amount of available assets
    /// @return The amount of available assets
    function _availableAssets() internal view returns (uint256) {
        return
            IERC20(_asset()).balanceOf(address(this)) - _getTotalLockedSpread();
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShare() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            (_totalAssets() - _getTotalLockedSpread() - _getTotalFairValue())
                .div(_totalSupply());
    }

    /// @notice Checks if a listing exists within internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
    /// @return If listing exists, return true, otherwise false
    function _contains(
        uint256 strike,
        uint256 maturity
    ) internal view returns (bool) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (!l.maturities.contains(maturity)) return false;

        return l.maturityToStrikes[maturity].contains(strike);
    }

    /// @notice Adds a listing to the internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
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

    /// @notice Removes a listing from internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
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

    /// @inheritdoc ERC4626BaseInternal
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

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            revert Vault__ZeroShares();
        } else {
            assetAmount = shareAmount.mul(_getPricePerShare());
        }
    }

    /// @inheritdoc ERC4626BaseInternal
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

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        return _convertToShares(_maxWithdraw(owner));
    }

    /// @inheritdoc ERC4626BaseInternal
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

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        if (_totalSupply() == 0) revert Vault__ZeroShares();
        if (_totalAssets() == 0) revert Vault__InsufficientFunds();
        shareAmount = assetAmount.div(_getPricePerShare());
    }

    /// @inheritdoc ERC4626BaseInternal
    function _afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual override {
        if (receiver == address(0)) revert Vault__AddressZero();
        if (assetAmount == 0) revert Vault__ZeroAsset();
        if (shareAmount == 0) revert Vault__ZeroShares();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _beforeWithdraw(
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual override {
        if (owner == address(0)) revert Vault__AddressZero();
        if (assetAmount == 0) revert Vault__ZeroAsset();
        if (shareAmount == 0) revert Vault__ZeroShares();
    }

    /// @notice Ensures that the listing is supported by this vault to sell
    ///         options for
    /// @param spot The spot price
    /// @param strike The strike price of the listing
    /// @param tau The time until maturity (yrs) for corresponding to the listing
    /// @param sigma The implied volatility for the listing
    /// @param rfRate The risk-free rate
    function _ensureSupportedListing(
        uint256 spot,
        uint256 strike,
        uint256 tau,
        uint256 sigma,
        uint256 rfRate
    ) internal view {
        uint256 dte = tau.mul(365e18);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // DTE filter
        if (dte > l.maxDTE || dte < l.minDTE) revert Vault__MaturityBounds();

        // Delta filter
        int256 delta = OptionMath
            .optionDelta(spot, strike, tau, sigma, rfRate, l.isCall)
            .abs();

        if (delta < l.minDelta || delta > l.maxDelta)
            revert Vault__DeltaBounds();
    }

    /// @notice An internal hook inside the buy function that is called after
    ///         logic inside the buy function is run to update state variables
    /// @param args The arguments struct for this function.
    function _afterBuy(AfterBuyArgs memory args) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        _updateState();
        uint256 spreadRate = args.spread / args.secondsToExpiration;
        uint256 newLockedAssets = l.isCall
            ? args.size
            : args.size.mul(args.strike);

        l.spreadUnlockingRate += spreadRate;
        l.spreadUnlockingTicks[args.maturity] += spreadRate;
        l.totalLockedSpread += args.spread;
        l.totalLockedAssets += newLockedAssets;
        l.positionSizes[args.maturity][args.strike] += args.size;
        l.lastTradeTimestamp = block.timestamp;
    }

    /// @notice Gets the pool factory address corresponding to the given strike
    ///         and maturity.
    /// @param strike The strike price for the pool
    /// @param maturity The maturity for the pool
    /// @return The pool factory address
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

        address listingAddr = IPoolFactory(FACTORY).getPoolAddress(_poolKey);
        if (listingAddr == address(0)) revert Vault__OptionPoolNotListed();
        return listingAddr;
    }

    /// @notice Gets the C-level given an increase in collateral amount.
    /// @param collateralAmt The collateral amount the will be utilised.
    /// @return The C-level after utilising `collateralAmt`
    function _getCLevel(uint256 collateralAmt) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxCLevel == 0) revert Vault__CLevelBounds();
        if (l.alphaCLevel == 0) revert Vault__CLevelBounds();

        uint256 postUtilisation = (l.totalLockedAssets + collateralAmt).div(
            _totalAssets()
        );

        if (postUtilisation > ONE.toUint256()) revert Vault__UtilEstError();

        uint256 hoursSinceLastTx = (block.timestamp - l.lastTradeTimestamp).div(
            ONE_HOUR
        );

        uint256 cLevel = _calculateCLevel(
            postUtilisation,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel
        );

        // NOTE: cLevel may have underflow of 1 unit
        if (cLevel + 1 < l.minCLevel) revert Vault__lowCLevel();

        uint256 discount = l.hourlyDecayDiscount.mul(hoursSinceLastTx);

        if (cLevel - discount < l.minCLevel) return l.minCLevel;

        return cLevel - discount;
    }

    /// @notice Calculates the C-level given a post-utilisation value.
    ///         (https://www.desmos.com/calculator/0uzv50t7jy)
    /// @param postUtilisation The utilisation after some collateral is utilised
    /// @param alphaCLevel (needs to be filled in)
    /// @param minCLevel The minimum C-level
    /// @param maxCLevel The maximum C-level
    /// @return The C-level corresponding to the post-utilisation value.
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

    /// @notice Gets a quote for a given trade request
    /// @param args The trading arguments (documented in struct at top)
    function _quote(
        TradeArgs memory args
    ) internal view returns (address, uint256, uint256, uint256, uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Check non Zero Strike
        if (args.strike == 0) revert Vault__StrikeZero();
        // Check valid maturity
        if (block.timestamp >= args.maturity) revert Vault__OptionExpired();

        BlackScholesArgs memory bsArgs = BlackScholesArgs({
            spot: _getSpotPrice(),
            strike: args.strike,
            timeToMaturity: (args.maturity - block.timestamp).div(ONE_YEAR),
            volAnnualized: 0,
            riskFreeRate: IVolatilityOracle(IV_ORACLE).getRiskFreeRate(),
            isCall: l.isCall
        });

        bsArgs.volAnnualized = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            bsArgs.spot,
            bsArgs.strike,
            bsArgs.timeToMaturity
        );

        _ensureSupportedListing(
            bsArgs.spot,
            bsArgs.strike,
            bsArgs.timeToMaturity,
            bsArgs.volAnnualized,
            bsArgs.riskFreeRate
        );

        address poolAddr = _getFactoryAddress(args.strike, args.maturity);

        // returns USD price for calls & puts
        uint256 price = OptionMath.blackScholesPrice(
            bsArgs.spot,
            bsArgs.strike,
            bsArgs.timeToMaturity,
            bsArgs.volAnnualized,
            bsArgs.riskFreeRate,
            bsArgs.isCall
        );

        if (l.isCall) price = price.div(bsArgs.spot);

        // call denominated in base, put denominated in quote
        uint256 mintingFee = IPool(poolAddr).takerFee(
            args.size,
            price.mul(args.size),
            false
        );

        // Check if the vault has sufficient funds
        uint256 collateralAmt = l.isCall
            ? args.size
            : args.size.mul(args.strike);
        // todo: mintingFee is a transit item
        if (collateralAmt >= IERC20(_asset()).balanceOf(address(this)))
            revert Vault__InsufficientFunds();

        uint256 cLevel = _getCLevel(collateralAmt);
        uint256 spread = (cLevel - l.minCLevel).mul(price).mul(args.size);

        return (poolAddr, price.mul(args.size), mintingFee, cLevel, spread);
    }

    /// @notice Fulfills an option purchase
    /// @param args The trading arguments (documented in struct at top)
    function _buy(TradeArgs memory args) internal {
        // Get pool address, price and c-level
        (
            address poolAddr,
            uint256 premium,
            uint256 mintingFee,
            ,
            uint256 totalSpread
        ) = _quote(args);

        // Add listing
        _addListing(args.strike, args.maturity);

        // Collect option premium from buyer
        IERC20(_asset()).safeTransferFrom(
            msg.sender,
            address(this),
            premium + totalSpread + mintingFee
        );

        // Approve transfer of base / quote token
        IERC20(_asset()).approve(
            poolAddr,
            // todo: for puts multiply the size by the strike
            args.size + totalSpread + mintingFee
        );

        // Mint option and allocate long token
        IPool(poolAddr).writeFrom(address(this), msg.sender, args.size);

        uint256 secondsToExpiration = args.maturity - block.timestamp;

        // Handle the premiums and spread capture generated
        AfterBuyArgs memory intel = AfterBuyArgs(
            args.maturity,
            premium,
            secondsToExpiration,
            args.size,
            totalSpread,
            args.strike
        );
        _afterBuy(intel);

        emit Sell(
            msg.sender,
            args.strike,
            args.maturity,
            args.size,
            premium,
            totalSpread
        );
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
    ) external view returns (address, uint256, uint256, uint256, uint256) {
        TradeArgs memory args;
        args.strike = strike;
        args.maturity = maturity;
        args.size = size;
        return _quote(args);
    }

    /// @notice Settles all options that are on a single maturity
    /// @param maturity The maturity that options will be settled for
    function _settleMaturity(uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        for (uint256 i = 0; i < l.maturityToStrikes[maturity].length(); i++) {
            uint256 strike = l.maturityToStrikes[maturity].at(i);
            uint256 positionSize = l.positionSizes[maturity][strike];
            uint256 unlockedCollateral = l.isCall
                ? positionSize
                : positionSize.mul(strike);
            l.totalLockedAssets -= unlockedCollateral;
            address listingAddr = _getFactoryAddress(strike, maturity);
            uint256 settlementValue = IPool(listingAddr).settle(address(this));
            uint256 exerciseValue = unlockedCollateral - settlementValue;
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

        while (current <= lastExpired && current != 0) {
            _settleMaturity(current);

            // Remove maturity from data structure
            next = l.maturities.next(current);
            uint256 numStrikes = l.maturityToStrikes[current].length();
            for (uint256 i = 0; i < numStrikes; i++) {
                uint256 strike = l.maturityToStrikes[current].at(0);
                l.positionSizes[current][strike] = 0;
                _removeListing(strike, current);
            }
            current = next;
        }

        return 0;
    }
}
