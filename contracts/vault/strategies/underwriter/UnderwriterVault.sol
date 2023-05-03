// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ERC20BaseInternal} from "@solidstate/contracts/token/ERC20/base/ERC20BaseInternal.sol";
import {SolidStateERC4626} from "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {ERC4626BaseInternal} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseInternal.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {IUnderwriterVault, IVault} from "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IOracleAdapter} from "../../../adapter/IOracleAdapter.sol";
import {IPoolFactory} from "../../../factory/IPoolFactory.sol";
import {ZERO, ONE} from "../../../libraries/Constants.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../libraries/EnumerableSetUD60x18.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";
import {PRBMathExtra} from "../../../libraries/PRBMathExtra.sol";
import {IVolatilityOracle} from "../../../oracle/IVolatilityOracle.sol";
import {IPool} from "../../../pool/IPool.sol";

/// @title An ERC-4626 implementation for underwriting call/put option
///        contracts by using collateral deposited by users
contract UnderwriterVault is IUnderwriterVault, SolidStateERC4626 {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ONE_YEAR = 365 days;
    uint256 internal constant ONE_HOUR = 1 hours;

    address internal immutable FEE_RECEIVER;
    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;
    address internal immutable ROUTER;

    /// @notice The constructor for this vault
    /// @param oracleAddress The address for the volatility oracle
    /// @param factoryAddress The pool factory address
    constructor(
        address feeReceiver,
        address oracleAddress,
        address factoryAddress,
        address router
    ) {
        FEE_RECEIVER = feeReceiver;
        IV_ORACLE = oracleAddress;
        FACTORY = factoryAddress;
        ROUTER = router;
    }

    /// @notice Gets the timestamp of the current block.
    /// @dev We are using a virtual internal function to be able to override in Mock contract for testing purpose
    function _getBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view override returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetFromUD60x18(l.totalAssets);
    }

    /// @notice Gets the spot price at the current time
    /// @return The spot price at the current time
    function _getSpotPrice() internal view virtual returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return IOracleAdapter(l.oracleAdapter).quote(l.base, l.quote);
    }

    /// @notice Gets the spot price at the given timestamp
    /// @param timestamp The time to get the spot price for.
    /// @return The spot price at the given timestamp
    function _getSettlementPrice(
        uint256 timestamp
    ) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            IOracleAdapter(l.oracleAdapter).quoteFrom(
                l.base,
                l.quote,
                timestamp
            );
    }

    /// @notice Gets the total liabilities value of the basket of expired
    ///         options underwritten by this vault at the current time
    /// @return The total liabilities of the basket of expired options underwritten
    function _getTotalLiabilitiesExpired() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;
        UD60x18 total = ZERO;

        while (current <= _getBlockTimestamp() && current != 0) {
            UD60x18 settlement = _getSettlementPrice(current);

            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                UD60x18 strike = l.maturityToStrikes[current].at(i);

                UD60x18 price = OptionMath.blackScholesPrice(
                    settlement,
                    strike,
                    ZERO,
                    ONE,
                    ZERO,
                    l.isCall
                );

                UD60x18 size = l.positionSizes[current][strike];
                UD60x18 premium = l.isCall ? (price / settlement) : price;
                total = total + premium * size;
            }

            current = l.maturities.next(current);
        }

        return total;
    }

    /// @notice Gets the total liabilities value of the basket of unexpired
    ///         options underwritten by this vault at the current time
    /// @return The the total liabilities of the basket of unexpired options underwritten
    function _getTotalLiabilitiesUnexpired() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 timestamp = _getBlockTimestamp();

        if (l.maxMaturity <= timestamp) return ZERO;

        uint256 current = l.getMaturityAfterTimestamp(timestamp);
        UD60x18 total = ZERO;

        // Compute fair value for options that have not expired
        uint256 n = l.getNumberOfUnexpiredListings(timestamp);

        UnexpiredListingVars memory vars = UnexpiredListingVars({
            spot: _getSpotPrice(),
            riskFreeRate: IVolatilityOracle(IV_ORACLE).getRiskFreeRate(),
            strikes: new UD60x18[](n),
            timeToMaturities: new UD60x18[](n),
            maturities: new uint256[](n),
            sigmas: new UD60x18[](n)
        });

        uint256 i = 0;
        while (current <= l.maxMaturity && current != 0) {
            UD60x18 timeToMaturity = UD60x18.wrap((current - timestamp) * WAD) /
                UD60x18.wrap(OptionMath.ONE_YEAR_TTM * WAD);

            for (
                uint256 j = 0;
                j < l.maturityToStrikes[current].length();
                j++
            ) {
                vars.strikes[i] = l.maturityToStrikes[current].at(j);
                vars.timeToMaturities[i] = timeToMaturity;
                vars.maturities[i] = current;
                i++;
            }

            current = l.maturities.next(current);
        }

        vars.sigmas = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            vars.spot,
            vars.strikes,
            vars.timeToMaturities
        );

        for (uint256 k = 0; k < n; k++) {
            UD60x18 price = OptionMath.blackScholesPrice(
                vars.spot,
                vars.strikes[k],
                vars.timeToMaturities[k],
                vars.sigmas[k],
                vars.riskFreeRate,
                l.isCall
            );
            UD60x18 size = l.positionSizes[vars.maturities[k]][vars.strikes[k]];
            total = total + price * size;
        }

        return l.isCall ? total / vars.spot : total;
    }

    /// @notice Gets the total liabilities of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total liabilities of the basket of options underwritten
    function _getTotalLiabilities() internal view returns (UD60x18) {
        return _getTotalLiabilitiesUnexpired() + _getTotalLiabilitiesExpired();
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
    /// @return vars The total locked spread
    function _getLockedSpreadInternal()
        internal
        view
        returns (LockedSpreadInternal memory vars)
    {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = l.getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);
        uint256 timestamp = _getBlockTimestamp();

        vars.spreadUnlockingRate = l.spreadUnlockingRate;
        vars.totalLockedSpread = l.totalLockedSpread;
        vars.lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;

        while (current <= timestamp && current != 0) {
            vars.totalLockedSpread =
                vars.totalLockedSpread -
                UD60x18.wrap((current - vars.lastSpreadUnlockUpdate) * WAD) *
                vars.spreadUnlockingRate;

            vars.spreadUnlockingRate =
                vars.spreadUnlockingRate -
                l.spreadUnlockingTicks[current];
            vars.lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
        }

        vars.totalLockedSpread =
            vars.totalLockedSpread -
            UD60x18.wrap((timestamp - vars.lastSpreadUnlockUpdate) * WAD) *
            vars.spreadUnlockingRate;
        vars.lastSpreadUnlockUpdate = timestamp;
    }

    function _balanceOfUD60x18(address owner) internal view returns (UD60x18) {
        // NOTE: _balanceOf returns the balance of the ERC20 share token which is always in 18 decimal places.
        // therefore no further scaling has to be applied
        return UD60x18.wrap(_balanceOf(owner));
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
    function _availableAssetsUD60x18() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return
            l.totalAssets -
            l.totalLockedAssets -
            _getLockedSpreadInternal().totalLockedSpread;
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShareUD60x18() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 supply = _totalSupplyUD60x18();

        if ((supply != ZERO) && (l.totalAssets != ZERO))
            return
                (_availableAssetsUD60x18() + _getTotalFairValue()) /
                _totalSupplyUD60x18();

        return ONE;
    }

    function _getAveragePricePerShareUD60x18(
        address owner
    ) internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 assets = l.netUserDeposits[owner];
        UD60x18 shares = _balanceOfUD60x18(owner);
        return assets / shares;
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (l.maxMaturity > l.lastSpreadUnlockUpdate) {
            LockedSpreadInternal memory vars = _getLockedSpreadInternal();

            l.totalLockedSpread = vars.totalLockedSpread;
            l.spreadUnlockingRate = vars.spreadUnlockingRate;
            l.lastSpreadUnlockUpdate = vars.lastSpreadUnlockUpdate;
        }
    }

    function _convertToSharesUD60x18(
        UD60x18 assetAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            shareAmount = assetAmount;
        } else {
            if (l.totalAssets == ZERO) {
                shareAmount = assetAmount;
            } else {
                shareAmount = assetAmount / pps;
            }
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToShares(
        uint256 assetAmount
    ) internal view override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 pps = _getPricePerShareUD60x18();
        return
            _convertToSharesUD60x18(l.convertAssetToUD60x18(assetAmount), pps)
                .unwrap();
    }

    function _convertToAssetsUD60x18(
        UD60x18 shareAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 assetAmount) {
        UD60x18 supply = _totalSupplyUD60x18();

        if (supply == ZERO) {
            revert Vault__ZeroShares();
        } else {
            assetAmount = shareAmount * pps;
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 assets = _convertToAssetsUD60x18(
            UD60x18.wrap(shareAmount),
            pps
        );
        assetAmount = l.convertAssetFromUD60x18(assets);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _deposit(
        uint256 assetAmount,
        address receiver
    ) internal virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (assetAmount > _maxDeposit(receiver))
            revert Vault__MaximumAmountExceeded(
                l.convertAssetToUD60x18(_maxDeposit(receiver)),
                l.convertAssetToUD60x18(assetAmount)
            );

        shareAmount = _previewDeposit(assetAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
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

    /// @inheritdoc ERC4626BaseInternal
    function _mint(
        uint256 shareAmount,
        address receiver
    ) internal virtual override returns (uint256 assetAmount) {
        if (shareAmount > _maxMint(receiver))
            revert Vault__MaximumAmountExceeded(
                UD60x18.wrap(_maxMint(receiver)),
                UD60x18.wrap(shareAmount)
            );

        assetAmount = _previewMint(shareAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    function _maxRedeemUD60x18(
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }

        UD60x18 assets = _maxWithdrawUD60x18(owner, pps);

        return assets / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        UD60x18 pps = _getPricePerShareUD60x18();
        return _maxRedeemUD60x18(owner, pps).unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) internal virtual override returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 shares = UD60x18.wrap(shareAmount);
        UD60x18 pps = _getPricePerShareUD60x18();

        if (shares > _maxRedeemUD60x18(owner, pps))
            revert Vault__MaximumAmountExceeded(
                _maxRedeemUD60x18(owner, pps),
                shares
            );

        UD60x18 assets = shares * pps;
        assetAmount = l.convertAssetFromUD60x18(assets);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _maxWithdrawUD60x18(
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 withdrawableAssets) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }

        UD60x18 balance = _balanceOfUD60x18(owner);

        FeeInternal memory vars = _getFeeInternal(owner, balance, pps);
        UD60x18 sharesOwner = _maxTransferableShares(vars);

        UD60x18 assetsOwner = sharesOwner * pps;
        UD60x18 availableAssets = _availableAssetsUD60x18();

        if (assetsOwner > availableAssets) {
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

        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 assets = _maxWithdrawUD60x18(owner, pps);

        withdrawableAssets = l.convertAssetFromUD60x18(assets);
    }

    function _previewWithdrawUD60x18(
        UD60x18 assetAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        if (_totalSupplyUD60x18() == ZERO) revert Vault__ZeroShares();
        if (_availableAssetsUD60x18() == ZERO)
            revert Vault__InsufficientFunds();
        shareAmount = assetAmount / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        UD60x18 assets = l.convertAssetToUD60x18(assetAmount);

        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 shares = _previewWithdrawUD60x18(assets, pps);
        shareAmount = shares.unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    ) internal virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 assets = l.convertAssetToUD60x18(assetAmount);
        UD60x18 pps = _getPricePerShareUD60x18();

        if (assets > _maxWithdrawUD60x18(owner, pps))
            revert Vault__MaximumAmountExceeded(
                _maxWithdrawUD60x18(owner, pps),
                assets
            );

        UD60x18 shares = _previewWithdrawUD60x18(assets, pps);
        shareAmount = shares.unwrap();

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _updateTimeOfDeposit(address owner, uint256 shareAmount) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 balance = _balanceOfUD60x18(owner);
        UD60x18 shares = UD60x18.wrap(shareAmount);
        UD60x18 timestamp = UD60x18.wrap(_getBlockTimestamp() * WAD);
        UD60x18 depositTimestamp = UD60x18.wrap(l.timeOfDeposit[owner] * WAD);

        UD60x18 updated = (depositTimestamp * balance + timestamp * shares) /
            (balance + shares);

        l.timeOfDeposit[owner] = updated.unwrap() / WAD;
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

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Add assetAmount deposited to user's balance
        // This is needed to compute average price per share
        UD60x18 assets = l.convertAssetToUD60x18(assetAmount);

        l.netUserDeposits[receiver] = l.netUserDeposits[receiver] + assets;
        l.totalAssets = l.totalAssets + assets;

        _updateTimeOfDeposit(receiver, shareAmount);

        emit UpdateQuotes();
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

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        _beforeTokenTransfer(owner, address(this), shareAmount);

        // Remove the assets from totalAssets
        UD60x18 assets = l.convertAssetToUD60x18(assetAmount);
        l.totalAssets = l.totalAssets - assets;

        emit UpdateQuotes();
    }

    /// @notice An internal hook inside the buy function that is called after
    ///         logic inside the buy function is run to update state variables
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    /// @param size The amount of contracts.
    /// @param spread The spread added on to the premium due to C-level
    function _afterBuy(
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size,
        UD60x18 spread
    ) internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        uint256 secondsToExpiration = maturity - _getBlockTimestamp();

        _updateState();
        UD60x18 spreadRate = spread / UD60x18.wrap(secondsToExpiration * WAD);
        UD60x18 collateral = l.isCall ? size : size * strike;

        l.spreadUnlockingRate = l.spreadUnlockingRate + spreadRate;
        l.spreadUnlockingTicks[maturity] =
            l.spreadUnlockingTicks[maturity] +
            spreadRate;
        l.totalLockedSpread = l.totalLockedSpread + spread;
        l.totalLockedAssets = l.totalLockedAssets + collateral;
        l.positionSizes[maturity][strike] =
            l.positionSizes[maturity][strike] +
            size;
        l.lastTradeTimestamp = _getBlockTimestamp();
    }

    /// @notice Gets the pool address corresponding to the given strike and maturity.
    /// @param strike The strike price for the pool
    /// @param maturity The maturity for the pool
    /// @return The pool factory address
    function _getPoolAddress(
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

        (address pool, bool isDeployed) = IPoolFactory(FACTORY).getPoolAddress(
            _poolKey
        );
        if (!isDeployed) revert Vault__OptionPoolNotListed();
        return pool;
    }

    /// @notice Calculates the C-level given a utilisation value and time since last trade value (duration).
    ///         (https://www.desmos.com/calculator/0uzv50t7jy)
    /// @param utilisation The utilisation after some collateral is utilised
    /// @param duration The time since last trade (hours)
    /// @param alpha (needs to be filled in)
    /// @param minCLevel The minimum C-level
    /// @param maxCLevel The maximum C-level
    /// @param decayRate The decay rate of the C-level back down to minimum level (decay/hour)
    /// @return The C-level corresponding to the post-utilisation value.
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

    /// @notice Ensures that an option is tradeable with the vault.
    /// @param size The amount of contracts.
    function _ensureNonZeroSize(UD60x18 size) internal pure {
        if (size == ZERO) revert Vault__ZeroSize();
    }

    /// @notice Ensures that an option is tradeable with the vault.
    /// @param isCallVault Whether the vault is a call or put vault.
    /// @param isCallOption Whether the option is a call or put.
    /// @param isBuy Whether the trade is a buy or a sell.
    function _ensureTradeableWithVault(
        bool isCallVault,
        bool isCallOption,
        bool isBuy
    ) internal pure {
        if (!isBuy) revert Vault__TradeMustBeBuy();
        if (isCallOption != isCallVault)
            revert Vault__OptionTypeMismatchWithVault();
    }

    /// @notice Ensures that an option is valid for trading.
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    function _ensureValidOption(
        UD60x18 strike,
        uint256 maturity
    ) internal view {
        // Check non Zero Strike
        if (strike == ZERO) revert Vault__StrikeZero();
        // Check valid maturity
        if (_getBlockTimestamp() >= maturity)
            revert Vault__OptionExpired(_getBlockTimestamp(), maturity);
    }

    /// @notice Ensures there is sufficient funds for processing a trade.
    /// @param isCallVault Whether the vault is a call or put vault.
    /// @param strike The strike price.
    /// @param size The amount of contracts.
    /// @param availableAssets The amount of available assets currently in the vault.
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

    /// @notice Ensures that a value is within the DTE bounds.
    /// @param value The observed value of the variable.
    /// @param minimum The minimum value the variable can be.
    /// @param maximum The maximum value the variable can be.
    function _ensureWithinDTEBounds(
        UD60x18 value,
        UD60x18 minimum,
        UD60x18 maximum
    ) internal pure {
        if (value < minimum || value > maximum) revert Vault__OutOfDTEBounds();
    }

    /// @notice Ensures that a value is within the delta bounds.
    /// @param value The observed value of the variable.
    /// @param minimum The minimum value the variable can be.
    /// @param maximum The maximum value the variable can be.
    function _ensureWithinDeltaBounds(
        SD59x18 value,
        SD59x18 minimum,
        SD59x18 maximum
    ) internal pure {
        if (value < minimum || value > maximum)
            revert Vault__OutOfDeltaBounds();
    }

    /// @notice Ensures that a value is within the delta bounds.
    /// @param totalPremium The total premium of the trade
    /// @param premiumLimit The premium limit of the trade
    /// @param isBuy Whether the trade is a buy or a sell.
    function _ensureBelowTradeMaxSlippage(
        UD60x18 totalPremium,
        UD60x18 premiumLimit,
        bool isBuy
    ) internal pure {
        if (isBuy && totalPremium > premiumLimit)
            revert Vault__AboveMaxSlippage(totalPremium, premiumLimit);
        if (!isBuy && totalPremium < premiumLimit)
            revert Vault__AboveMaxSlippage(totalPremium, premiumLimit);
    }

    /// @notice Get the variables needed in order to compute the quote for a trade.
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    /// @param isCall Whether the option is a call or a put.
    /// @param size The amount of contracts.
    /// @param isBuy Whether the trade is a buy or a sell.
    /// @return quote The variables needed in order to compute the quote for a trade.
    function _getQuoteInternal(
        UD60x18 strike,
        uint256 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) internal view returns (QuoteInternal memory quote) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 timestamp = _getBlockTimestamp();

        _ensureNonZeroSize(size);
        _ensureTradeableWithVault(l.isCall, isCall, isBuy);
        _ensureValidOption(strike, maturity);
        _ensureSufficientFunds(isCall, strike, size, _availableAssetsUD60x18());

        address pool = _getPoolAddress(strike, maturity);

        QuoteVars memory vars;

        vars.spot = _getSpotPrice();

        // Compute time until maturity and check bounds
        vars.tau =
            UD60x18.wrap((maturity - timestamp) * WAD) /
            UD60x18.wrap(ONE_YEAR * WAD);
        _ensureWithinDTEBounds(
            vars.tau * UD60x18.wrap(365e18),
            l.minDTE,
            l.maxDTE
        );

        vars.sigma = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            vars.spot,
            strike,
            vars.tau
        );
        vars.riskFreeRate = IVolatilityOracle(IV_ORACLE).getRiskFreeRate();

        // Compute delta and check bounds
        vars.delta = OptionMath
            .optionDelta(
                vars.spot,
                strike,
                vars.tau,
                vars.sigma,
                vars.riskFreeRate,
                l.isCall
            )
            .abs();
        _ensureWithinDeltaBounds(vars.delta, l.minDelta, l.maxDelta);

        vars.price = OptionMath.blackScholesPrice(
            vars.spot,
            strike,
            vars.tau,
            vars.sigma,
            vars.riskFreeRate,
            l.isCall
        );
        vars.price = l.isCall ? vars.price / vars.spot : vars.price;

        // Compute C-level
        UD60x18 collateral = l.isCall ? size : size * strike;
        UD60x18 utilisation = (l.totalLockedAssets + collateral) /
            l.totalAssets;
        UD60x18 hoursSinceLastTx = UD60x18.wrap(
            (timestamp - l.lastTradeTimestamp) * WAD
        ) / UD60x18.wrap(ONE_HOUR * WAD);

        vars.cLevel = _computeCLevel(
            utilisation,
            hoursSinceLastTx,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel,
            l.hourlyDecayDiscount
        );

        // Compute output variables
        quote.pool = pool;
        quote.premium = vars.price * size;
        quote.spread = (vars.cLevel - l.minCLevel) * quote.premium;
        quote.mintingFee = l.convertAssetToUD60x18(
            IPool(quote.pool).takerFee(address(0), size, 0, true) // ToDo : Implement takerFee vxPremia discount
        );
        return quote;
    }

    /// @inheritdoc IVault
    function getQuote(
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premium) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        QuoteInternal memory quote = _getQuoteInternal(
            strike,
            maturity,
            isCall,
            size,
            isBuy
        );

        premium = l.convertAssetFromUD60x18(
            quote.premium + quote.spread + quote.mintingFee
        );
    }

    /// @inheritdoc IVault
    function trade(
        UD60x18 strike,
        uint64 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit
    ) external override {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        QuoteInternal memory quote = _getQuoteInternal(
            strike,
            maturity,
            isCall,
            size,
            isBuy
        );
        UD60x18 totalPremium = quote.premium + quote.spread + quote.mintingFee;

        _ensureBelowTradeMaxSlippage(
            totalPremium,
            l.convertAssetToUD60x18(premiumLimit),
            isBuy
        );

        // Add listing
        l.addListing(strike, maturity);

        // Add everything except mintingFee
        l.totalAssets = l.totalAssets + quote.premium + quote.spread;

        // Collect option premium from buyer
        uint256 transferAmountScaled = l.convertAssetFromUD60x18(totalPremium);

        IERC20(_asset()).safeTransferFrom(
            msg.sender,
            address(this),
            transferAmountScaled
        );

        // Approve transfer of base / quote token
        UD60x18 collateral = l.isCall ? size : size * strike;
        uint256 approveAmountScaled = l.convertAssetFromUD60x18(
            collateral + quote.mintingFee
        );

        IERC20(_asset()).approve(ROUTER, approveAmountScaled);

        // Mint option and allocate long token
        IPool(quote.pool).writeFrom(address(this), msg.sender, size);

        // Handle the premiums and spread capture generated
        _afterBuy(strike, maturity, size, quote.spread);

        // Emit trade event
        emit Trade(
            msg.sender,
            quote.pool,
            size,
            true,
            totalPremium,
            quote.mintingFee,
            ZERO,
            quote.spread
        );

        // Emit event for updated quotes
        emit UpdateQuotes();
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
            address pool = _getPoolAddress(strike, maturity);
            UD60x18 collateralValue = l.convertAssetToUD60x18(
                IPool(pool).settle(address(this))
            );
            l.totalAssets =
                l.totalAssets -
                (unlockedCollateral - collateralValue);
        }
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external override {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // Needs to update state as settle effects the listed postions, i.e. maturities and maturityToStrikes.
        _updateState();
        // Get last maturity that is greater than the current time
        uint256 lastExpired;
        uint256 timestamp = _getBlockTimestamp();

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

        // Claim protocol fees
        _claimFees();

        emit UpdateQuotes();
    }

    /// @notice Computes the fee variables needed for computed performance and management fees.
    /// @param owner The owner of the shares.
    /// @param shares The amount of shares to be transferred.
    /// @param pps The price per share.
    /// @return The fee variables needed for computed performance and management fees.
    function _getFeeInternal(
        address owner,
        UD60x18 shares,
        UD60x18 pps
    ) internal view returns (FeeInternal memory) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 timestamp = _getBlockTimestamp();

        FeeInternal memory vars;

        vars.balanceShares = _balanceOfUD60x18(owner);

        UD60x18 ppsAvg;
        UD60x18 performance;
        if (vars.balanceShares > ZERO) {
            ppsAvg = _getAveragePricePerShareUD60x18(owner);
            performance = pps / ppsAvg;
            vars.assets = shares * pps;
        }

        UD60x18 performanceFeeInShares;

        if (performance > ONE) {
            performanceFeeInShares =
                shares *
                (performance - ONE) *
                l.performanceFeeRate;

            vars.performanceFeeInAssets = performanceFeeInShares * pps;
        }

        // Time since last deposit in years
        UD60x18 timeSinceLastDeposit = UD60x18.wrap(
            (timestamp - l.timeOfDeposit[owner]) * WAD
        ) / UD60x18.wrap(OptionMath.ONE_YEAR_TTM * WAD);

        UD60x18 managementFeeInShares = vars.balanceShares *
            l.managementFeeRate *
            timeSinceLastDeposit;
        vars.managementFeeInAssets = _convertToAssetsUD60x18(
            managementFeeInShares,
            pps
        );

        vars.totalFeeInShares = managementFeeInShares + performanceFeeInShares;
        vars.totalFeeInAssets =
            vars.managementFeeInAssets +
            vars.performanceFeeInAssets;

        return vars;
    }

    /// @notice Gets the maximum amount of shares a user can transfer.
    /// @param vars The variables needed to compute fees.
    /// @return The maximum amount of shares a user can transfer.
    function _maxTransferableShares(
        FeeInternal memory vars
    ) internal pure returns (UD60x18) {
        if (vars.balanceShares == ZERO) return ZERO;
        return vars.balanceShares - vars.totalFeeInShares;
    }

    /// @inheritdoc ERC20BaseInternal
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        super._beforeTokenTransfer(from, to, amount);
        if (from != address(0) && to != address(0)) {
            UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
                .layout();

            UD60x18 shares = UD60x18.wrap(amount);

            UD60x18 pps = _getPricePerShareUD60x18();

            FeeInternal memory vars = _getFeeInternal(from, shares, pps);

            UD60x18 maxShares = _maxTransferableShares(vars);

            if (shares > maxShares)
                revert Vault__TransferExceedsBalance(maxShares, shares);

            if (vars.totalFeeInShares > ZERO) {
                _burn(from, vars.totalFeeInShares.unwrap());
            }

            // fees collected denominated in the reference token
            // fees are tracked in order to keep the pps unaffected during the burn
            // (totalAssets - feeInShares * pps) / (totalSupply - feeInShares) = pps
            l.protocolFees = l.protocolFees + vars.totalFeeInAssets;
            l.totalAssets = l.totalAssets - vars.totalFeeInAssets;

            if (vars.performance > ONE) {
                emit PerformanceFeePaid(
                    FEE_RECEIVER,
                    vars.performanceFeeInAssets.unwrap()
                );
            }
            emit ManagementFeePaid(
                FEE_RECEIVER,
                vars.managementFeeInAssets.unwrap()
            );

            // need to increment totalShares by the feeInShares such that we can adjust netUserDeposits
            UD60x18 fractionKept = (vars.balanceShares -
                shares -
                vars.totalFeeInShares) / vars.balanceShares;

            l.netUserDeposits[from] = l.netUserDeposits[from] * fractionKept;

            if (to != address(this)) {
                l.netUserDeposits[to] = l.netUserDeposits[to] + vars.assets;
                _updateTimeOfDeposit(to, amount);
            }

            emit UpdateQuotes();
        }
    }

    /// @notice Transfers fees to the FEE_RECEIVER.
    function _claimFees() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 claimedFees = l.convertAssetFromUD60x18(l.protocolFees);

        l.protocolFees = ZERO;
        IERC20(_asset()).safeTransfer(FEE_RECEIVER, claimedFees);

        emit ClaimProtocolFees(
            FEE_RECEIVER,
            l.convertAssetToUD60x18(claimedFees)
        );
    }
}
