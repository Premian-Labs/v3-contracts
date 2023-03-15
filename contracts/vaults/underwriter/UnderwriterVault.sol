// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SolidStateERC4626} from "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {ERC4626BaseInternal} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IUnderwriterVault} from "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/volatility/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {IPoolFactory} from "../../factory/IPoolFactory.sol";
import {IPool} from "../../pool/IPool.sol";
import {IOracleAdapter} from "../../oracle/price/IOracleAdapter.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";
import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../libraries/EnumerableSetUD60x18.sol";
import {PRBMathExtra} from "../../libraries/PRBMathExtra.sol";

/// @title An ERC-4626 implementation for underwriting call/put option
///        contracts by using collateral deposited by users
contract UnderwriterVault is
    IUnderwriterVault,
    SolidStateERC4626,
    OwnableInternal
{
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;

    SD59x18 internal constant iZERO = SD59x18.wrap(0);
    SD59x18 internal constant iONE = SD59x18.wrap(1e18);
    UD60x18 internal constant ZERO = UD60x18.wrap(0);
    UD60x18 internal constant ONE = UD60x18.wrap(1e18);

    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant ONE_HOUR = 1 hours;

    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;
    address internal immutable ROUTER;

    // The structs below are used as a way to reduce stack depth and avoid "stack too deep" errors
    struct AfterBuyArgs {
        // The maturity of a listing
        uint256 maturity;
        // The vanilla Black-Scholes premium paid by the option buyer
        UD60x18 premium;
        // The time until maturity (seconds) for the listing
        uint256 secondsToExpiration;
        // The number of contracts for an option purchase
        UD60x18 size;
        // The spread captured from selling an option
        UD60x18 spread;
        // The strike of a listing
        UD60x18 strike;
    }

    struct BlackScholesArgs {
        // The spot price
        UD60x18 spot;
        // The strike price of the listing
        UD60x18 strike;
        // The time until maturity (years)
        UD60x18 timeToMaturity;
        // The implied volatility for the listing
        UD60x18 volAnnualized;
        // The risk-free rate
        UD60x18 riskFreeRate;
        // Whether the option is a buy or a sell
        bool isCall;
    }

    struct TradeArgs {
        // The strike price of the listing
        UD60x18 strike;
        // The maturity of the listing
        uint256 maturity;
        // The number of contracts being traded
        UD60x18 size;
    }

    struct QuoteReturnVars {
        address poolAddr;
        UD60x18 premium;
        UD60x18 mintingFee;
        UD60x18 cLevel;
        UD60x18 totalSpread;
    }

    struct UnexpiredListingVars {
        // A list of strikes for a set of listings
        UD60x18[] strikes;
        // A list of time until maturity (years) for a set of listings
        UD60x18[] timeToMaturities;
        // A list of maturities for a set of listings
        uint256[] maturities;
    }

    /// @notice The constructor for this vault
    /// @param oracleAddress The address for the volatility oracle
    /// @param factoryAddress The pool factory address
    constructor(address oracleAddress, address factoryAddress, address router) {
        IV_ORACLE = oracleAddress;
        FACTORY = factoryAddress;
        ROUTER = router;
    }

    function _totalAssetsUD60x18() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 balanceOf = IERC20(_asset()).balanceOf(address(this));
        // TODO: FIX THIS
        return UD60x18.wrap(balanceOf) / l.totalLockedAssets;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view override returns (uint256) {
        return _totalAssetsUD60x18().unwrap();
    }

    /// @notice Gets the total locked spread currently stored in storage
    /// @return The total locked spread in stored in storage
    function _totalLockedSpread() internal view returns (UD60x18) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    /// @notice Gets the spot price at the current time
    /// @return The spot price at the current time
    function _getSpotPrice() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(UnderwriterVaultStorage.layout().oracleAdapter)
                .quote(l.base, l.quote);
    }

    /// @notice Gets the spot price at the given timestamp
    /// @param timestamp The given timestamp
    /// @return The spot price at the given timestamp
    function _getSpotPrice(uint256 timestamp) internal view returns (UD60x18) {
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

    /// @notice Gets the total liabilities value of the basket of expired
    ///         options underwritten by this vault at the current time
    /// @param timestamp The given timestamp
    /// @return The total liabilities of the basket of expired options underwritten
    function _getTotalLiabilitiesExpired(
        uint256 timestamp
    ) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;
        UD60x18 total = ZERO;

        while (current <= timestamp && current != 0) {
            UD60x18 spot = _getSpotPrice(current);

            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                UD60x18 strike = l.maturityToStrikes[current].at(i);

                UD60x18 price = OptionMath.blackScholesPrice(
                    spot,
                    strike,
                    ZERO,
                    ONE,
                    ZERO,
                    l.isCall
                );

                UD60x18 size = l.positionSizes[current][strike];
                UD60x18 premium = l.isCall ? (price / spot) : price;
                total = total + premium * size;
            }

            current = l.maturities.next(current);
        }

        return total;
    }

    /// @notice Gets the total liabilities value of the basket of unexpired
    ///         options underwritten by this vault at the current time
    /// @param timestamp The given timestamp
    /// @param spot The spot price
    /// @return The the total liabilities of the basket of unexpired options underwritten
    function _getTotalLiabilitiesUnexpired(
        uint256 timestamp,
        UD60x18 spot
    ) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity <= timestamp) return ZERO;

        uint256 current = _getMaturityAfterTimestamp(timestamp);
        UD60x18 total = ZERO;

        // Compute fair value for options that have not expired
        uint256 n = _getNumberOfUnexpiredListings(timestamp);

        UnexpiredListingVars memory listings = UnexpiredListingVars({
            strikes: new UD60x18[](n),
            timeToMaturities: new UD60x18[](n),
            maturities: new uint256[](n)
        });

        uint256 i = 0;
        while (current <= l.maxMaturity && current != 0) {
            UD60x18 timeToMaturity = UD60x18.wrap(
                (current - timestamp) * 1e18
            ) / UD60x18.wrap(365 * 24 * 60 * 60 * 1e18);

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

        UD60x18[] memory sigmas = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            spot,
            listings.strikes,
            listings.timeToMaturities
        );

        for (uint256 k = 0; k < n; k++) {
            UD60x18 price = OptionMath.blackScholesPrice(
                spot,
                listings.strikes[k],
                listings.timeToMaturities[k],
                sigmas[k],
                ZERO,
                l.isCall
            );

            UD60x18 size = l.positionSizes[listings.maturities[k]][
                listings.strikes[k]
            ];
            total = total + price * size;
        }

        return l.isCall ? total / spot : total;
    }

    /// @notice Gets the total liabilities of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total liabilities of the basket of options underwritten
    function _getTotalLiabilities() internal view returns (UD60x18) {
        uint256 timestamp = block.timestamp;
        UD60x18 spot = _getSpotPrice();
        return
            _getTotalLiabilitiesUnexpired(timestamp, spot) +
            _getTotalLiabilitiesExpired(timestamp);
    }

    /// @notice Gets the total fair value of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total fair value of the basket of options underwritten
    function _getTotalFairValue() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.totalLockedAssets - _getTotalLiabilities();
    }

    /// @notice Gets the total locked spread for the vault
    /// @return The total locked spread
    function _getTotalLockedSpread() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity <= l.lastSpreadUnlockUpdate) return ZERO;

        uint256 current = _getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        UD60x18 spreadUnlockingRate = l.spreadUnlockingRate;
        // TODO: double check handling of negative total locked spread
        UD60x18 totalLockedSpread = l.totalLockedSpread;
        uint256 timestamp = block.timestamp;

        while (current <= timestamp && current != 0) {
            totalLockedSpread =
                totalLockedSpread -
                UD60x18.wrap((current - lastSpreadUnlockUpdate) * 1e18) *
                spreadUnlockingRate;

            spreadUnlockingRate =
                spreadUnlockingRate -
                l.spreadUnlockingTicks[current];
            lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
        }
        totalLockedSpread =
            totalLockedSpread -
            UD60x18.wrap((timestamp - lastSpreadUnlockUpdate) * 1e18) *
            spreadUnlockingRate;
        return totalLockedSpread;
    }

    function _balanceOfUD60x18() internal view returns (UD60x18) {
        return UD60x18.wrap(_balanceOf());
    }

    function _balanceOf() internal view returns (uint256) {
        return IERC20(_asset()).balanceOf(address(this));
    }

    function _totalSupplyUD60x18() internal view returns (UD60x18) {
        return UD60x18.wrap(_totalSupply());
    }

    /// @notice Gets the current amount of available assets
    /// @return The amount of available assets
    // TODO: shouldn't this include lockedAssets?
    function _availableAssets() internal view returns (UD60x18) {
        return _balanceOfUD60x18() - _getTotalLockedSpread();
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShare() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            (_balanceOfUD60x18() -
                _getTotalLockedSpread() +
                _getTotalFairValue()) / _totalSupplyUD60x18();
    }

    /// @notice Checks if a listing exists within internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
    /// @return If listing exists, return true, otherwise false
    function _contains(
        UD60x18 strike,
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
    function _addListing(UD60x18 strike, uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

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
    function _removeListing(UD60x18 strike, uint256 maturity) internal {
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
            UD60x18 spreadUnlockingRate = l.spreadUnlockingRate;
            UD60x18 totalLockedSpread = l.totalLockedSpread;

            uint256 timestamp = block.timestamp;

            while (current <= timestamp && current != 0) {
                totalLockedSpread =
                    totalLockedSpread -
                    UD60x18.wrap((current - lastSpreadUnlockUpdate) * 1e18) *
                    spreadUnlockingRate;

                spreadUnlockingRate =
                    spreadUnlockingRate -
                    l.spreadUnlockingTicks[current];
                lastSpreadUnlockUpdate = current;
                current = l.maturities.next(current);
            }
            totalLockedSpread =
                totalLockedSpread -
                UD60x18.wrap((timestamp - lastSpreadUnlockUpdate) * 1e18) *
                spreadUnlockingRate;

            l.totalLockedSpread = totalLockedSpread;
            l.spreadUnlockingRate = spreadUnlockingRate;
            l.lastSpreadUnlockUpdate = timestamp;
        }
    }

    function _convertToSharesUD60x18(
        UD60x18 assetAmount
    ) internal view returns (UD60x18 shareAmount) {
        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            shareAmount = assetAmount;
        } else {
            UD60x18 totalAssets = _totalAssetsUD60x18();
            if (totalAssets == ZERO) {
                shareAmount = assetAmount;
            } else {
                shareAmount = assetAmount / _getPricePerShare();
            }
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToShares(
        uint256 assetAmount
    ) internal view override returns (uint256 shareAmount) {
        return _convertToSharesUD60x18(UD60x18.wrap(assetAmount)).unwrap();
    }

    function _convertToAssetsUD60x18(
        UD60x18 shareAmount
    ) internal view returns (UD60x18 assetAmount) {
        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            revert Vault__ZeroShares();
        } else {
            assetAmount = shareAmount * _getPricePerShare();
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        return _convertToAssetsUD60x18(UD60x18.wrap(shareAmount)).unwrap();
    }

    function _maxWithdrawUD60x18(
        address owner
    ) internal view returns (UD60x18 withdrawableAssets) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }

        UD60x18 assetsOwner = UD60x18.wrap(_convertToAssets(_balanceOf(owner)));
        UD60x18 availableAssets = _availableAssets();

        if (assetsOwner >= availableAssets) {
            withdrawableAssets = availableAssets;
        } else {
            withdrawableAssets = assetsOwner;
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxWithdraw(
        address owner
    ) internal view virtual override returns (uint256 withdrawableAssets) {
        return _maxWithdrawUD60x18(owner).unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        return _convertToShares(_maxWithdraw(owner));
    }

    function _previewMintUD60x18(
        UD60x18 shareAmount
    ) internal view returns (UD60x18 assetAmount) {
        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            assetAmount = shareAmount;
        } else {
            assetAmount = shareAmount * _getPricePerShare();
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewMint(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        return _previewMintUD60x18(UD60x18.wrap(shareAmount)).unwrap();
    }

    function _previewWithdrawUD60x18(
        UD60x18 assetAmount
    ) internal view returns (UD60x18 shareAmount) {
        if (_totalSupplyUD60x18() == ZERO) revert Vault__ZeroShares();
        if (_totalAssetsUD60x18() == ZERO) revert Vault__InsufficientFunds();
        shareAmount = assetAmount / _getPricePerShare();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        return _previewMintUD60x18(UD60x18.wrap(assetAmount)).unwrap();
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
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 tau,
        UD60x18 sigma,
        UD60x18 rfRate
    ) internal view {
        UD60x18 dte = tau * UD60x18.wrap(365e18);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // DTE filter
        if (dte > l.maxDTE || dte < l.minDTE) revert Vault__MaturityBounds();

        // Delta filter
        SD59x18 delta = OptionMath
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
        uint256 timestamp = block.timestamp;

        _updateState();
        UD60x18 spreadRate = args.spread /
            UD60x18.wrap(args.secondsToExpiration * 1e18);
        UD60x18 newLockedAssets = l.isCall
            ? args.size
            : args.size * args.strike;

        l.spreadUnlockingRate = l.spreadUnlockingRate + spreadRate;
        l.spreadUnlockingTicks[args.maturity] =
            l.spreadUnlockingTicks[args.maturity] +
            spreadRate;
        l.totalLockedSpread = l.totalLockedSpread + args.spread;
        l.totalLockedAssets = l.totalLockedAssets + newLockedAssets;
        l.positionSizes[args.maturity][args.strike] =
            l.positionSizes[args.maturity][args.strike] +
            args.size;
        l.lastTradeTimestamp = timestamp;
    }

    /// @notice Gets the pool factory address corresponding to the given strike
    ///         and maturity.
    /// @param strike The strike price for the pool
    /// @param maturity The maturity for the pool
    /// @return The pool factory address
    function _getFactoryAddress(
        UD60x18 strike,
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
    function _getCLevel(UD60x18 collateralAmt) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxCLevel == ZERO) revert Vault__CLevelBounds();
        if (l.alphaCLevel == ZERO) revert Vault__CLevelBounds();

        UD60x18 postUtilisation = (l.totalLockedAssets + collateralAmt) /
            _totalAssetsUD60x18();

        if (postUtilisation > ONE) revert Vault__UtilEstError();

        UD60x18 hoursSinceLastTx = UD60x18.wrap(
            (block.timestamp - l.lastTradeTimestamp) * 1e18
        ) / UD60x18.wrap(ONE_HOUR * 1e18);

        UD60x18 cLevel = _calculateCLevel(
            postUtilisation,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel
        );

        // NOTE: cLevel may have underflow of 1 unit
        if (cLevel + ONE < l.minCLevel) revert Vault__lowCLevel();

        UD60x18 discount = l.hourlyDecayDiscount * hoursSinceLastTx;

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
        UD60x18 postUtilisation,
        UD60x18 alphaCLevel,
        UD60x18 minCLevel,
        UD60x18 maxCLevel
    ) internal pure returns (UD60x18) {
        UD60x18 freeCapitalRatio = ONE - postUtilisation;
        UD60x18 positiveExp = (alphaCLevel * freeCapitalRatio).exp();
        UD60x18 alphaCLevelExp = alphaCLevel.exp();
        UD60x18 k = (alphaCLevel * (minCLevel * alphaCLevelExp - maxCLevel)) /
            (alphaCLevelExp - ONE);

        return
            (k * positiveExp + maxCLevel * alphaCLevel - k) /
            (alphaCLevel * positiveExp);
    }

    /// @notice Gets a quote for a given trade request
    /// @param args The trading arguments (documented in struct at top)
    function _quote(
        TradeArgs memory args
    ) internal view returns (address, UD60x18, UD60x18, UD60x18, UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 timestamp = block.timestamp;

        // Check non Zero Strike
        if (args.strike == ZERO) revert Vault__StrikeZero();
        // Check valid maturity
        if (timestamp >= args.maturity) revert Vault__OptionExpired();

        BlackScholesArgs memory bsArgs = BlackScholesArgs({
            spot: _getSpotPrice(),
            strike: args.strike,
            timeToMaturity: UD60x18.wrap((args.maturity - timestamp) * 1e18) /
                UD60x18.wrap(ONE_YEAR * 1e18),
            volAnnualized: ZERO,
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

        // returns USD price for calls & puts
        UD60x18 price = OptionMath.blackScholesPrice(
            bsArgs.spot,
            bsArgs.strike,
            bsArgs.timeToMaturity,
            bsArgs.volAnnualized,
            bsArgs.riskFreeRate,
            bsArgs.isCall
        );

        if (l.isCall) price = price / bsArgs.spot;

        // call denominated in base, put denominated in quote
        QuoteReturnVars memory vars;
        vars.poolAddr = _getFactoryAddress(args.strike, args.maturity);
        vars.premium = price * args.size;

        vars.mintingFee = UD60x18.wrap(
            IPool(vars.poolAddr).takerFee(
                args.size,
                vars.premium.unwrap(),
                false
            )
        );

        // Check if the vault has sufficient funds
        UD60x18 collateralAmt = l.isCall ? args.size : args.size * args.strike;
        // todo: mintingFee is a transit item
        if (collateralAmt >= _availableAssets())
            revert Vault__InsufficientFunds();

        vars.cLevel = _getCLevel(collateralAmt);
        vars.totalSpread = (vars.cLevel - l.minCLevel) * vars.premium;

        return (
            vars.poolAddr,
            vars.premium,
            vars.mintingFee,
            vars.cLevel,
            vars.totalSpread
        );
    }

    /// @notice Fulfills an option purchase
    /// @param args The trading arguments (documented in struct at top)
    function _buy(TradeArgs memory args) internal {
        // Get pool address, price and c-level
        (
            address poolAddr,
            UD60x18 premium,
            UD60x18 mintingFee,
            ,
            UD60x18 totalSpread
        ) = _quote(args);

        // Add listing
        _addListing(args.strike, args.maturity);

        // Collect option premium from buyer
        IERC20(_asset()).safeTransferFrom(
            msg.sender,
            address(this),
            (premium + totalSpread + mintingFee).unwrap()
        );

        // Approve transfer of base / quote token
        IERC20(_asset()).approve(
            ROUTER,
            // todo: for puts multiply the size by the strike
            (args.size + totalSpread + mintingFee).unwrap()
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
            args.strike.unwrap(),
            args.maturity,
            args.size.unwrap(),
            premium.unwrap(),
            totalSpread.unwrap()
        );
    }

    /// @inheritdoc IUnderwriterVault
    function buy(uint256 strike, uint256 maturity, uint256 size) external {
        TradeArgs memory args;
        args.strike = UD60x18.wrap(strike);
        args.maturity = maturity;
        args.size = UD60x18.wrap(size);
        return _buy(args);
    }

    /// @inheritdoc IUnderwriterVault
    function quote(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external view returns (address, uint256, uint256, uint256, uint256) {
        TradeArgs memory args;
        args.strike = UD60x18.wrap(strike);
        args.maturity = maturity;
        args.size = UD60x18.wrap(size);
        (
            address poolAddr,
            UD60x18 premium,
            UD60x18 mintingFee,
            UD60x18 cLevel,
            UD60x18 spread
        ) = _quote(args);
        return (
            poolAddr,
            premium.unwrap(),
            mintingFee.unwrap(),
            cLevel.unwrap(),
            spread.unwrap()
        );
    }

    /// @notice Settles all options that are on a single maturity
    /// @param maturity The maturity that options will be settled for
    function _settleMaturity(uint256 maturity) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        for (uint256 i = 0; i < l.maturityToStrikes[maturity].length(); i++) {
            UD60x18 strike = l.maturityToStrikes[maturity].at(i);
            UD60x18 positionSize = l.positionSizes[maturity][strike];
            UD60x18 unlockedCollateral = l.isCall
                ? positionSize
                : positionSize * strike;
            l.totalLockedAssets = l.totalLockedAssets - unlockedCollateral;
            address listingAddr = _getFactoryAddress(strike, maturity);
            IPool(listingAddr).settle(address(this));
        }
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external override returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // Get last maturity that is greater than the current time
        uint256 lastExpired;
        uint256 timestamp = block.timestamp;

        if (timestamp >= l.maxMaturity) {
            lastExpired = l.maxMaturity;
        } else {
            lastExpired = _getMaturityAfterTimestamp(timestamp);
            lastExpired = l.maturities.prev(lastExpired);
        }

        uint256 current = l.minMaturity;

        while (current <= lastExpired && current != 0) {
            _settleMaturity(current);

            // Remove maturity from data structure
            uint256 next = l.maturities.next(current);
            uint256 numStrikes = l.maturityToStrikes[current].length();
            for (uint256 i = 0; i < numStrikes; i++) {
                UD60x18 strike = l.maturityToStrikes[current].at(0);
                l.positionSizes[current][strike] = ZERO;
                _removeListing(strike, current);
            }
            current = next;
        }

        return 0;
    }
}
