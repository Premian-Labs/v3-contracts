// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {SolidStateERC4626} from "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {ERC4626BaseInternal} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {IUnderwriterVault, IVault} from "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../../oracle/volatility/IVolatilityOracle.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";
import {IPoolFactory} from "../../../factory/IPoolFactory.sol";
import {IPool} from "../../../pool/IPool.sol";
import {IOracleAdapter} from "../../../oracle/price/IOracleAdapter.sol";
import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../../../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../libraries/EnumerableSetUD60x18.sol";
import {ZERO, iZERO, ONE, iONE} from "../../../libraries/Constants.sol";
import {PRBMathExtra} from "../../../libraries/PRBMathExtra.sol";

import "hardhat/console.sol";

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
    using PRBMathExtra for UD60x18;

    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant ONE_HOUR = 1 hours;

    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;
    address internal immutable ROUTER;

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
        return _balanceOfAssetUD60x18(address(this)) + l.totalLockedAssets;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view override returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetFromUD60x18(_totalAssetsUD60x18());
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
        return IOracleAdapter(l.oracleAdapter).quote(l.base, l.quote);
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

        uint256 current = l.getMaturityAfterTimestamp(timestamp);
        UD60x18 total = ZERO;

        // Compute fair value for options that have not expired
        uint256 n = l.getNumberOfUnexpiredListings(timestamp);

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
    function _getTotalLiabilities(
        uint256 timestamp
    ) internal view returns (UD60x18) {
        UD60x18 spot = _getSpotPrice();
        return
            _getTotalLiabilitiesUnexpired(timestamp, spot) +
            _getTotalLiabilitiesExpired(timestamp);
    }

    /// @notice Gets the total fair value of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total fair value of the basket of options underwritten
    function _getTotalFairValue(
        uint256 timestamp
    ) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.totalLockedAssets - _getTotalLiabilities(timestamp);
    }

    /// @notice Gets the total locked spread for the vault
    /// @return The total locked spread
    function _getLockedSpreadVars(
        uint256 timestamp
    ) internal view returns (LockedSpreadVars memory) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = l.getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);

        LockedSpreadVars memory vars;
        vars.spreadUnlockingRate = l.spreadUnlockingRate;
        vars.totalLockedSpread = l.totalLockedSpread;
        vars.lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;

        while (current <= timestamp && current != 0) {
            vars.totalLockedSpread =
                vars.totalLockedSpread -
                UD60x18.wrap((current - vars.lastSpreadUnlockUpdate) * 1e18) *
                vars.spreadUnlockingRate;

            vars.spreadUnlockingRate =
                vars.spreadUnlockingRate -
                l.spreadUnlockingTicks[current];
            vars.lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
        }

        vars.totalLockedSpread =
            vars.totalLockedSpread -
            UD60x18.wrap((timestamp - vars.lastSpreadUnlockUpdate) * 1e18) *
            vars.spreadUnlockingRate;
        vars.lastSpreadUnlockUpdate = timestamp;
        return vars;
    }

    function _balanceOfAssetUD60x18(
        address owner
    ) internal view returns (UD60x18 balanceScaled) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 balance = IERC20(_asset()).balanceOf(owner);
        balanceScaled = l.convertAssetToUD60x18(balance);
    }

    function _balanceOfAsset(address owner) internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetFromUD60x18(_balanceOfAssetUD60x18(owner));
    }

    function _totalSupplyUD60x18() internal view returns (UD60x18) {
        return UD60x18.wrap(_totalSupply());
    }

    /// @notice Gets the current amount of available assets
    /// @return The amount of available assets
    // TODO: shouldn't this include lockedAssets?
    function _availableAssetsUD60x18() internal view returns (UD60x18) {
        return
            _balanceOfAssetUD60x18(address(this)) -
            _getLockedSpreadVars(block.timestamp).totalLockedSpread;
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShareUD60x18() internal view returns (UD60x18) {
        return
            (_balanceOfAssetUD60x18(address(this)) -
                _getLockedSpreadVars(block.timestamp).totalLockedSpread +
                _getTotalFairValue(block.timestamp)) / _totalSupplyUD60x18();
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState(uint256 timestamp) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity > l.lastSpreadUnlockUpdate) {
            LockedSpreadVars memory vars = _getLockedSpreadVars(timestamp);

            l.totalLockedSpread = vars.totalLockedSpread;
            l.spreadUnlockingRate = vars.spreadUnlockingRate;
            l.lastSpreadUnlockUpdate = vars.lastSpreadUnlockUpdate;
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
                shareAmount = assetAmount / _getPricePerShareUD60x18();
            }
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToShares(
        uint256 assetAmount
    ) internal view override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            _convertToSharesUD60x18(l.convertAssetToUD60x18(assetAmount))
                .unwrap();
    }

    function _convertToAssetsUD60x18(
        UD60x18 shareAmount
    ) internal view returns (UD60x18 assetAmount) {
        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            revert Vault__ZeroShares();
        } else {
            assetAmount = shareAmount * _getPricePerShareUD60x18();
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 assets = _convertToAssetsUD60x18(UD60x18.wrap(shareAmount));
        assetAmount = l.convertAssetFromUD60x18(assets);
    }

    function _balanceOfUD60x18(address owner) internal view returns (UD60x18) {
        // NOTE: _balanceOf returns the balance of the ERC20 share token which is always in 18 decimal places.
        // therefore no further scaling has to be applied
        return UD60x18.wrap(_balanceOf(owner));
    }

    function _maxWithdrawUD60x18(
        address owner
    ) internal view returns (UD60x18 withdrawableAssets) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }
        UD60x18 assetsOwner = _convertToAssetsUD60x18(_balanceOfUD60x18(owner));
        UD60x18 availableAssets = _availableAssetsUD60x18();

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
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 assets = _maxWithdrawUD60x18(owner);
        withdrawableAssets = l.convertAssetFromUD60x18(assets);
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
            assetAmount = shareAmount * _getPricePerShareUD60x18();
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewMint(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 assets = _previewMintUD60x18(UD60x18.wrap(shareAmount));
        assetAmount = l.convertAssetFromUD60x18(assets);
    }

    function _previewWithdrawUD60x18(
        UD60x18 assetAmount
    ) internal view returns (UD60x18 shareAmount) {
        if (_totalSupplyUD60x18() == ZERO) revert Vault__ZeroShares();
        if (_totalAssetsUD60x18() == ZERO) revert Vault__InsufficientFunds();
        shareAmount = assetAmount / _getPricePerShareUD60x18();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 assetAmountScaled = l.convertAssetToUD60x18(assetAmount);
        shareAmount = _previewMintUD60x18(assetAmountScaled).unwrap();
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

    /// @notice An internal hook inside the buy function that is called after
    ///         logic inside the buy function is run to update state variables
    /// @param vars The arguments struct for this function.
    function _afterBuy(QuoteVars memory vars) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        uint256 secondsToExpiration = vars.maturity - vars.timestamp;

        _updateState(vars.timestamp);
        UD60x18 spreadRate = vars.spread /
            UD60x18.wrap(secondsToExpiration * 1e18);
        UD60x18 newLockedAssets = l.isCall
            ? vars.size
            : vars.size * vars.strike;

        l.spreadUnlockingRate = l.spreadUnlockingRate + spreadRate;
        l.spreadUnlockingTicks[vars.maturity] =
            l.spreadUnlockingTicks[vars.maturity] +
            spreadRate;
        l.totalLockedSpread = l.totalLockedSpread + vars.spread;
        l.totalLockedAssets = l.totalLockedAssets + newLockedAssets;
        l.positionSizes[vars.maturity][vars.strike] =
            l.positionSizes[vars.maturity][vars.strike] +
            vars.size;
        l.lastTradeTimestamp = vars.timestamp;
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
        if (cLevel + ONE < l.minCLevel) revert Vault__LowCLevel();

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

    function _computeCLevel(
        UD60x18 utilisation,
        UD60x18 duration,
        UD60x18 alpha,
        UD60x18 minCLevel,
        UD60x18 maxCLevel,
        UD60x18 decayRate
    ) internal pure returns (UD60x18) {
        if (utilisation > ONE) revert Vault__UtilisationOutOfBounds();

        UD60x18 posExp = (alpha * (ONE - utilisation)).exp();
        UD60x18 alphaExp = alpha.exp();
        UD60x18 k = (alpha * (minCLevel * alphaExp - maxCLevel)) /
            (alphaExp - ONE);

        UD60x18 cLevel = (k * posExp + maxCLevel * alpha - k) /
            (alpha * posExp);

        return PRBMathExtra.max(cLevel - decayRate * duration, minCLevel);
    }

    function _ensureTradeableWithVault(
        bool isCallVault,
        bool isCallOption,
        bool isBuy
    ) internal pure {
        if (!isBuy) revert Vault__TradeMustBeBuy();
        if (isCallOption != isCallVault)
            revert Vault__OptionTypeMismatchWithVault();
    }

    function _ensureValidOption(
        uint256 timestamp,
        UD60x18 strike,
        uint256 maturity
    ) internal pure {
        // Check non Zero Strike
        if (strike == ZERO) revert Vault__StrikeZero();
        // Check valid maturity
        if (timestamp >= maturity) revert Vault__OptionExpired();
    }

    function _ensureSufficientFunds(
        bool isCallVault,
        UD60x18 strike,
        UD60x18 size,
        UD60x18 availableAssets
    ) internal pure {
        // Check if the vault has sufficient funds
        UD60x18 collateral = isCallVault ? size : size * strike;
        if (collateral >= availableAssets) revert Vault__InsufficientFunds();
    }

    function _ensureWithinTradeBounds(
        UD60x18 value,
        UD60x18 minimum,
        UD60x18 maximum
    ) internal pure {
        if (value < minimum || value > maximum)
            revert Vault__OutOfTradeBounds();
    }

    function _ensureWithinTradeBounds(
        SD59x18 value,
        SD59x18 minimum,
        SD59x18 maximum
    ) internal pure {
        if (value < minimum || value > maximum)
            revert Vault__OutOfTradeBounds();
    }

    function _getQuoteVars(
        uint256 timestamp,
        UD60x18 spot,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size
    ) internal view returns (QuoteVars memory) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        QuoteVars memory vars;

        vars.timestamp = timestamp;
        vars.spot = spot;
        vars.strike = strike;
        vars.maturity = maturity;
        vars.poolAddr = _getFactoryAddress(vars.strike, vars.maturity);
        vars.tau =
            UD60x18.wrap((maturity - timestamp) * 1e18) /
            UD60x18.wrap(ONE_YEAR * 1e18);
        vars.sigma = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            vars.spot,
            vars.strike,
            vars.tau
        );
        vars.riskFreeRate = IVolatilityOracle(IV_ORACLE).getRiskFreeRate();
        vars.delta = OptionMath
            .optionDelta(
                vars.spot,
                vars.strike,
                vars.tau,
                vars.sigma,
                vars.riskFreeRate,
                l.isCall
            )
            .abs();
        vars.price = OptionMath.blackScholesPrice(
            vars.spot,
            vars.strike,
            vars.tau,
            vars.sigma,
            vars.riskFreeRate,
            l.isCall
        );
        vars.price = l.isCall ? vars.price : vars.price / vars.spot;
        vars.size = size;

        vars.premium = vars.price * vars.size;

        // Compute C-level
        UD60x18 collateral = l.isCall ? vars.size : vars.size * vars.strike;
        UD60x18 utilisation = (l.totalLockedAssets + collateral) /
            _totalAssetsUD60x18();
        UD60x18 hoursSinceLastTx = UD60x18.wrap(
            (vars.timestamp - l.lastTradeTimestamp) * 1e18
        ) / UD60x18.wrap(ONE_HOUR * 1e18);

        vars.cLevel = _computeCLevel(
            utilisation,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel,
            l.hourlyDecayDiscount,
            hoursSinceLastTx
        );

        vars.spread = (vars.cLevel - l.minCLevel) * vars.premium;

        vars.mintingFee = UD60x18.wrap(
            IPool(vars.poolAddr).takerFee(
                vars.size,
                vars.premium.unwrap(),
                false
            )
        );
        return vars;
    }

    function _getTradeQuote(
        uint256 timestamp,
        UD60x18 spot,
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) internal view returns (uint256 maxSize, uint256 price) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        _ensureTradeableWithVault(l.isCall, isCall, isBuy);
        _ensureValidOption(timestamp, strike, maturity);
        _ensureSufficientFunds(isCall, strike, size, _availableAssetsUD60x18());

        QuoteVars memory vars = _getQuoteVars(
            timestamp,
            spot,
            strike,
            maturity,
            size
        );

        _ensureWithinTradeBounds(vars.delta, l.minDelta, l.maxDelta);
        _ensureWithinTradeBounds(
            vars.tau * UD60x18.wrap(365e18),
            l.minDTE,
            l.maxDTE
        );

        maxSize = _availableAssetsUD60x18().unwrap();
        price = vars.premium.unwrap();
    }

    /// @inheritdoc IVault
    function getTradeQuote(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external view returns (uint256 maxSize, uint256 price) {
        return
            _getTradeQuote(
                block.timestamp,
                _getSpotPrice(),
                UD60x18.wrap(strike),
                maturity,
                isCall,
                UD60x18.wrap(size),
                isBuy
            );
    }

    function _trade(
        UD60x18 spot,
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 timestamp = block.timestamp;

        _ensureTradeableWithVault(l.isCall, isCall, isBuy);
        _ensureValidOption(block.timestamp, strike, maturity);
        _ensureSufficientFunds(isCall, strike, size, _availableAssetsUD60x18());

        QuoteVars memory vars = _getQuoteVars(
            timestamp,
            spot,
            strike,
            maturity,
            size
        );

        _ensureWithinTradeBounds(vars.delta, l.minDelta, l.maxDelta);
        _ensureWithinTradeBounds(
            vars.tau * UD60x18.wrap(365e18),
            l.minDTE,
            l.maxDTE
        );

        // Add listing
        l.addListing(vars.strike, vars.maturity);

        // Collect option premium from buyer
        uint256 transferAmountScaled = l.convertAssetFromUD60x18(
            vars.premium + vars.spread + vars.mintingFee
        );

        IERC20(_asset()).safeTransferFrom(
            msg.sender,
            address(this),
            transferAmountScaled
        );

        // Approve transfer of base / quote token
        // TODO: for puts multiply the size by the strike
        uint256 approveAmountScaled = l.convertAssetFromUD60x18(
            vars.size + vars.spread + vars.mintingFee
        );

        IERC20(_asset()).approve(ROUTER, approveAmountScaled);

        // Mint option and allocate long token
        IPool(vars.poolAddr).writeFrom(address(this), msg.sender, vars.size);

        // Handle the premiums and spread capture generated
        _afterBuy(vars);

        emit Trade(
            msg.sender,
            vars.poolAddr,
            vars.size,
            false,
            vars.premium + vars.spread + vars.mintingFee,
            vars.mintingFee,
            UD60x18.wrap(uint256(0)),
            vars.spread
        );
    }

    /// @inheritdoc IVault
    function trade(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external override {
        return
            _trade(
                _getSpotPrice(),
                UD60x18.wrap(strike),
                maturity,
                isCall,
                UD60x18.wrap(size),
                isBuy
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
        // Needs to update state as settle effects the listed postions, i.e. maturities and maturityToStrikes.
        _updateState(block.timestamp);
        // Get last maturity that is greater than the current time
        uint256 lastExpired;
        uint256 timestamp = block.timestamp;

        if (timestamp >= l.maxMaturity) {
            lastExpired = l.maxMaturity;
        } else {
            lastExpired = l.getMaturityAfterTimestamp(timestamp);
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
                l.removeListing(strike, current);
            }
            current = next;
        }

        return 0;
    }
}
