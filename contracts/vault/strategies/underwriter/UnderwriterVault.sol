// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
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

    address internal immutable VAULT_REGISTRY;
    address internal immutable FEE_RECEIVER;
    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;
    address internal immutable ROUTER;

    /// @notice The constructor for this vault
    /// @param oracleAddress The address for the volatility oracle
    /// @param factoryAddress The pool factory address
    constructor(
        address vaultRegistry,
        address feeReceiver,
        address oracleAddress,
        address factoryAddress,
        address router
    ) {
        VAULT_REGISTRY = vaultRegistry;
        FEE_RECEIVER = feeReceiver;
        IV_ORACLE = oracleAddress;
        FACTORY = factoryAddress;
        ROUTER = router;
    }

    function updateSettings(bytes memory settings) external {
        if (msg.sender != VAULT_REGISTRY)
            revert Vault__SettingsNotFromRegistry();

        // Decode data and update storage variable
        UnderwriterVaultStorage.layout().updateSettings(settings);
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
        UnderwriterVaultStorage.Layout storage l,
        uint256 timestamp
    ) internal view returns (UD60x18) {
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
    function _getTotalLiabilitiesExpired(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18) {
        // Compute fair value for expired unsettled options
        uint256 current = l.minMaturity;

        UD60x18 total;
        while (current <= _getBlockTimestamp() && current != 0) {
            UD60x18 settlement = _getSettlementPrice(l, current);

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

                UD60x18 premium = l.isCall ? (price / settlement) : price;
                total = total + premium * l.positionSizes[current][strike];
            }

            current = l.maturities.next(current);
        }

        return total;
    }

    /// @notice Gets the total liabilities value of the basket of unexpired
    ///         options underwritten by this vault at the current time
    /// @return The the total liabilities of the basket of unexpired options underwritten
    function _getTotalLiabilitiesUnexpired(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18) {
        uint256 timestamp = _getBlockTimestamp();

        if (l.maxMaturity <= timestamp) return ZERO;

        uint256 current = l.getMaturityAfterTimestamp(timestamp);
        UD60x18 total;

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
            for (
                uint256 j = 0;
                j < l.maturityToStrikes[current].length();
                j++
            ) {
                vars.strikes[i] = l.maturityToStrikes[current].at(j);
                vars.timeToMaturities[i] =
                    ud((current - timestamp) * WAD) /
                    ud(OptionMath.ONE_YEAR_TTM * WAD);
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
            total =
                total +
                price *
                l.positionSizes[vars.maturities[k]][vars.strikes[k]];
        }

        return l.isCall ? total / vars.spot : total;
    }

    /// @notice Gets the total liabilities of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total liabilities of the basket of options underwritten
    function _getTotalLiabilities(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18) {
        return
            _getTotalLiabilitiesUnexpired(l) + _getTotalLiabilitiesExpired(l);
    }

    /// @notice Gets the total fair value of the basket of options underwritten
    ///         by this vault at the current time
    /// @return The total fair value of the basket of options underwritten
    function _getTotalFairValue(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18) {
        return l.totalLockedAssets - _getTotalLiabilities(l);
    }

    /// @notice Gets the total locked spread for the vault
    /// @return vars The total locked spread
    function _getLockedSpreadInternal(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (LockedSpreadInternal memory vars) {
        uint256 current = l.getMaturityAfterTimestamp(l.lastSpreadUnlockUpdate);
        uint256 timestamp = _getBlockTimestamp();

        vars.spreadUnlockingRate = l.spreadUnlockingRate;
        vars.totalLockedSpread = l.totalLockedSpread;
        vars.lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;

        while (current <= timestamp && current != 0) {
            vars.totalLockedSpread =
                vars.totalLockedSpread -
                ud((current - vars.lastSpreadUnlockUpdate) * WAD) *
                vars.spreadUnlockingRate;

            vars.spreadUnlockingRate =
                vars.spreadUnlockingRate -
                l.spreadUnlockingTicks[current];
            vars.lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
        }

        vars.totalLockedSpread =
            vars.totalLockedSpread -
            ud((timestamp - vars.lastSpreadUnlockUpdate) * WAD) *
            vars.spreadUnlockingRate;
        vars.lastSpreadUnlockUpdate = timestamp;
    }

    function _balanceOfUD60x18(address owner) internal view returns (UD60x18) {
        // NOTE: _balanceOf returns the balance of the ERC20 share token which is always in 18 decimal places.
        // therefore no further scaling has to be applied
        return ud(_balanceOf(owner));
    }

    function _totalSupplyUD60x18() internal view returns (UD60x18) {
        return ud(_totalSupply());
    }

    /// @notice Gets the current amount of available assets
    /// @return The amount of available assets
    function _availableAssetsUD60x18(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18) {
        return
            l.totalAssets -
            l.totalLockedAssets -
            _getLockedSpreadInternal(l).totalLockedSpread;
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShareUD60x18() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if ((_totalSupplyUD60x18() != ZERO) && (l.totalAssets != ZERO))
            return
                (_availableAssetsUD60x18(l) + _getTotalFairValue(l)) /
                _totalSupplyUD60x18();

        return ONE;
    }

    function _getAveragePricePerShareUD60x18(
        address owner
    ) internal view returns (UD60x18) {
        return
            UnderwriterVaultStorage.layout().netUserDeposits[owner] /
            _balanceOfUD60x18(owner); // (assets / shares)
    }

    /// @notice updates total spread in storage to be able to compute the price per share
    function _updateState(UnderwriterVaultStorage.Layout storage l) internal {
        if (l.maxMaturity > l.lastSpreadUnlockUpdate) {
            LockedSpreadInternal memory vars = _getLockedSpreadInternal(l);

            l.totalLockedSpread = vars.totalLockedSpread;
            l.spreadUnlockingRate = vars.spreadUnlockingRate;
            l.lastSpreadUnlockUpdate = vars.lastSpreadUnlockUpdate;
        }
    }

    function _convertToSharesUD60x18(
        UD60x18 assetAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        if (_totalSupplyUD60x18() == ZERO) {
            shareAmount = assetAmount;
        } else {
            if (UnderwriterVaultStorage.layout().totalAssets == ZERO) {
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
        return
            _convertToSharesUD60x18(
                UnderwriterVaultStorage.layout().convertAssetToUD60x18(
                    assetAmount
                ),
                _getPricePerShareUD60x18()
            ).unwrap();
    }

    function _convertToAssetsUD60x18(
        UD60x18 shareAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 assetAmount) {
        if (_totalSupplyUD60x18() == ZERO) revert Vault__ZeroShares();

        assetAmount = shareAmount * pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        UD60x18 assets = _convertToAssetsUD60x18(
            ud(shareAmount),
            _getPricePerShareUD60x18()
        );
        assetAmount = UnderwriterVaultStorage.layout().convertAssetFromUD60x18(
            assets
        );
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
        assetAmount = _totalSupplyUD60x18() == ZERO
            ? shareAmount
            : shareAmount * _getPricePerShareUD60x18();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewMint(
        uint256 shareAmount
    ) internal view virtual override returns (uint256 assetAmount) {
        UD60x18 assets = _previewMintUD60x18(ud(shareAmount));
        assetAmount = UnderwriterVaultStorage.layout().convertAssetFromUD60x18(
            assets
        );
    }

    /// @inheritdoc ERC4626BaseInternal
    function _mint(
        uint256 shareAmount,
        address receiver
    ) internal virtual override returns (uint256 assetAmount) {
        if (shareAmount > _maxMint(receiver))
            revert Vault__MaximumAmountExceeded(
                ud(_maxMint(receiver)),
                ud(shareAmount)
            );

        assetAmount = _previewMint(shareAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    function _maxRedeemUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        if (owner == address(0)) revert Vault__AddressZero();

        return _maxWithdrawUD60x18(l, owner, pps) / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        return
            _maxRedeemUD60x18(
                UnderwriterVaultStorage.layout(),
                owner,
                _getPricePerShareUD60x18()
            ).unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) internal virtual override returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        UD60x18 shares = ud(shareAmount);
        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 maxRedeem = _maxRedeemUD60x18(l, owner, pps);

        if (shares > maxRedeem)
            revert Vault__MaximumAmountExceeded(maxRedeem, shares);

        assetAmount = l.convertAssetFromUD60x18(shares * pps);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _maxWithdrawUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 withdrawableAssets) {
        if (owner == address(0)) revert Vault__AddressZero();

        FeeInternal memory vars = _getFeeInternal(
            l,
            owner,
            _balanceOfUD60x18(owner),
            pps
        );
        UD60x18 assetsOwner = _maxTransferableShares(vars) * pps;
        UD60x18 availableAssets = _availableAssetsUD60x18(l);

        withdrawableAssets = assetsOwner > availableAssets
            ? availableAssets
            : assetsOwner;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxWithdraw(
        address owner
    ) internal view virtual override returns (uint256 withdrawableAssets) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        withdrawableAssets = l.convertAssetFromUD60x18(
            _maxWithdrawUD60x18(l, owner, _getPricePerShareUD60x18())
        );
    }

    function _previewWithdrawUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        UD60x18 assetAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        if (_totalSupplyUD60x18() == ZERO) revert Vault__ZeroShares();
        if (_availableAssetsUD60x18(l) == ZERO)
            revert Vault__InsufficientFunds();
        shareAmount = assetAmount / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        shareAmount = _previewWithdrawUD60x18(
            l,
            l.convertAssetToUD60x18(assetAmount),
            _getPricePerShareUD60x18()
        ).unwrap();
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
        UD60x18 maxWithdraw = _maxWithdrawUD60x18(l, owner, pps);

        if (assets > maxWithdraw)
            revert Vault__MaximumAmountExceeded(maxWithdraw, assets);

        shareAmount = _previewWithdrawUD60x18(l, assets, pps).unwrap();

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _updateTimeOfDeposit(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        uint256 shareBalanceBefore,
        uint256 shareAmount
    ) internal {
        l.timeOfDeposit[owner] =
            (l.timeOfDeposit[owner] *
                shareBalanceBefore +
                _getBlockTimestamp() *
                shareAmount) /
            (shareBalanceBefore + shareAmount);
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

        _updateTimeOfDeposit(
            l,
            receiver,
            _balanceOf(receiver) - shareAmount,
            shareAmount
        );

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
        l.totalAssets = l.totalAssets - l.convertAssetToUD60x18(assetAmount);

        emit UpdateQuotes();
    }

    /// @notice An internal hook inside the buy function that is called after
    ///         logic inside the buy function is run to update state variables
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    /// @param size The amount of contracts.
    /// @param spread The spread added on to the premium due to C-level
    function _afterBuy(
        UnderwriterVaultStorage.Layout storage l,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size,
        UD60x18 spread
    ) internal {
        // @magnus: spread state needs to be updated otherwise spread dispersion is inconsistent
        // we can make this function more efficient later on by not writing twice to storage, i.e.
        // compute the updated state, then increment values, then write to storage
        _updateState(l);
        UD60x18 spreadRate = spread /
            ud((maturity - _getBlockTimestamp()) * WAD);

        l.spreadUnlockingRate = l.spreadUnlockingRate + spreadRate;
        l.spreadUnlockingTicks[maturity] =
            l.spreadUnlockingTicks[maturity] +
            spreadRate;
        l.totalLockedSpread = l.totalLockedSpread + spread;
        l.totalLockedAssets = l.totalLockedAssets + l.collateral(size, strike);
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
        UnderwriterVaultStorage.Layout storage l,
        UD60x18 strike,
        uint256 maturity
    ) internal view returns (address) {
        // generate struct to grab pool address
        IPoolFactory.PoolKey memory _poolKey = IPoolFactory.PoolKey({
            base: l.base,
            quote: l.quote,
            oracleAdapter: l.oracleAdapter,
            strike: strike,
            maturity: maturity,
            isCallPool: l.isCall
        });

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
    function _revertIfZeroSize(UD60x18 size) internal pure {
        if (size == ZERO) revert Vault__ZeroSize();
    }

    /// @notice Ensures that an option is tradeable with the vault.
    /// @param isCallVault Whether the vault is a call or put vault.
    /// @param isCallOption Whether the option is a call or put.
    /// @param isBuy Whether the trade is a buy or a sell.
    function _revertIfNotTradeableWithVault(
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
    function _revertIfOptionInvalid(
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
    /// @param strike The strike price.
    /// @param size The amount of contracts.
    /// @param availableAssets The amount of available assets currently in the vault.
    function _revertIfInsufficientFunds(
        UD60x18 strike,
        UD60x18 size,
        UD60x18 availableAssets
    ) internal view {
        // Check if the vault has sufficient funds
        if (
            UnderwriterVaultStorage.layout().collateral(size, strike) >=
            availableAssets
        ) revert Vault__InsufficientFunds();
    }

    /// @notice Ensures that a value is within the DTE bounds.
    /// @param value The observed value of the variable.
    /// @param minimum The minimum value the variable can be.
    /// @param maximum The maximum value the variable can be.
    function _revertIfOutOfDTEBounds(
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
    function _revertIfOutOfDeltaBounds(
        UD60x18 value,
        UD60x18 minimum,
        UD60x18 maximum
    ) internal pure {
        if (value < minimum || value > maximum)
            revert Vault__OutOfDeltaBounds();
    }

    /// @notice Ensures that a value is within the delta bounds.
    /// @param totalPremium The total premium of the trade
    /// @param premiumLimit The premium limit of the trade
    /// @param isBuy Whether the trade is a buy or a sell.
    function _revertIfAboveTradeMaxSlippage(
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
    /// @param size The amount of contracts.
    /// @param isBuy Whether the trade is a buy or a sell.
    /// @return quote The variables needed in order to compute the quote for a trade.
    function _getQuoteInternal(
        UnderwriterVaultStorage.Layout storage l,
        UD60x18 strike,
        uint256 maturity,
        bool isCall,
        UD60x18 size,
        bool isBuy
    ) internal view returns (QuoteInternal memory quote) {
        _revertIfZeroSize(size);
        _revertIfNotTradeableWithVault(l.isCall, isCall, isBuy);
        _revertIfOptionInvalid(strike, maturity);
        _revertIfInsufficientFunds(strike, size, _availableAssetsUD60x18(l));

        quote.pool = _getPoolAddress(l, strike, maturity);

        QuoteVars memory vars;

        vars.spot = _getSpotPrice();

        // Compute time until maturity and check bounds
        vars.tau =
            ud((maturity - _getBlockTimestamp()) * WAD) /
            ud(ONE_YEAR * WAD);
        _revertIfOutOfDTEBounds(vars.tau * ud(365e18), l.minDTE, l.maxDTE);

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

        _revertIfOutOfDeltaBounds(
            vars.delta.intoUD60x18(),
            l.minDelta,
            l.maxDelta
        );

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
        UD60x18 utilisation = (l.totalLockedAssets +
            l.collateral(size, strike)) / l.totalAssets;
        UD60x18 hoursSinceLastTx = ud(
            (_getBlockTimestamp() - l.lastTradeTimestamp) * WAD
        ) / ud(ONE_HOUR * WAD);

        vars.cLevel = _computeCLevel(
            utilisation,
            hoursSinceLastTx,
            l.alphaCLevel,
            l.minCLevel,
            l.maxCLevel,
            l.hourlyDecayDiscount
        );

        // Compute output variables
        quote.premium = vars.price * size;
        quote.spread = (vars.cLevel - l.minCLevel) * quote.premium;
        quote.mintingFee = l.convertAssetToUD60x18(
            IPool(quote.pool).takerFee(address(0), size, 0, true) // ToDo : Implement takerFee vxPremia discount
        );
        return quote;
    }

    /// @inheritdoc IVault
    function getQuote(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premium) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        QuoteInternal memory quote = _getQuoteInternal(
            l,
            poolKey.strike,
            poolKey.maturity,
            poolKey.isCallPool,
            size,
            isBuy
        );

        premium = l.convertAssetFromUD60x18(
            quote.premium + quote.spread + quote.mintingFee
        );
    }

    /// @inheritdoc IVault
    function trade(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit
    ) external override {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        QuoteInternal memory quote = _getQuoteInternal(
            l,
            poolKey.strike,
            poolKey.maturity,
            poolKey.isCallPool,
            size,
            isBuy
        );
        UD60x18 totalPremium = quote.premium + quote.spread + quote.mintingFee;

        _revertIfAboveTradeMaxSlippage(
            totalPremium,
            l.convertAssetToUD60x18(premiumLimit),
            isBuy
        );

        // Add listing
        l.addListing(poolKey.strike, poolKey.maturity);

        // Add everything except mintingFee
        l.totalAssets = l.totalAssets + quote.premium + quote.spread;

        // Collect option premium from buyer
        IERC20(_asset()).safeTransferFrom(
            msg.sender,
            address(this),
            l.convertAssetFromUD60x18(totalPremium)
        );

        // Approve transfer of base / quote token
        uint256 approveAmountScaled = l.convertAssetFromUD60x18(
            l.collateral(size, poolKey.strike) + quote.mintingFee
        );

        IERC20(_asset()).approve(ROUTER, approveAmountScaled);

        // Mint option and allocate long token
        IPool(quote.pool).writeFrom(address(this), msg.sender, size);

        // Handle the premiums and spread capture generated
        _afterBuy(l, poolKey.strike, poolKey.maturity, size, quote.spread);

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
    function _settleMaturity(
        UnderwriterVaultStorage.Layout storage l,
        uint256 maturity
    ) internal {
        for (uint256 i = 0; i < l.maturityToStrikes[maturity].length(); i++) {
            UD60x18 strike = l.maturityToStrikes[maturity].at(i);
            UD60x18 positionSize = l.positionSizes[maturity][strike];
            UD60x18 unlockedCollateral = l.isCall
                ? positionSize
                : positionSize * strike;
            l.totalLockedAssets = l.totalLockedAssets - unlockedCollateral;
            address pool = _getPoolAddress(l, strike, maturity);
            UD60x18 collateralValue = l.convertAssetToUD60x18(
                IPool(pool).settle()
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
        _updateState(l);

        uint256 timestamp = _getBlockTimestamp();

        // Get last maturity that is greater than the current time
        uint256 lastExpired = timestamp >= l.maxMaturity
            ? l.maxMaturity
            : l.maturities.prev(l.getMaturityAfterTimestamp(timestamp));

        uint256 current = l.minMaturity;

        while (current <= lastExpired && current != 0) {
            _settleMaturity(l, current);

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
        _claimFees(l);

        emit UpdateQuotes();
    }

    /// @notice Computes the fee variables needed for computed performance and management fees.
    /// @param owner The owner of the shares.
    /// @param shares The amount of shares to be transferred.
    /// @param pps The price per share.
    /// @return The fee variables needed for computed performance and management fees.
    function _getFeeInternal(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        UD60x18 shares,
        UD60x18 pps
    ) internal view returns (FeeInternal memory) {
        FeeInternal memory vars;

        vars.balanceShares = _balanceOfUD60x18(owner);

        UD60x18 performance;
        if (vars.balanceShares > ZERO) {
            performance = pps / _getAveragePricePerShareUD60x18(owner);
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
            (_getBlockTimestamp() - l.timeOfDeposit[owner]) * WAD
        ) / UD60x18.wrap(OptionMath.ONE_YEAR_TTM * WAD);

        UD60x18 managementFeeInShares = shares *
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

        // mint: from = address(0), in this case no fees have to be paid
        // burn: to = address(0),
        //      1. fees are paid already in _beforeWithdraw, we do not want to double charge.
        //      2. furthermore, we need to call burn inside _beforeTokenTransfer, it would result in a nested call.
        //         we bypass this by calling _beforeWithdraw and using to = address(this).
        if (from != address(0) && to != address(0)) {
            UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
                .layout();

            UD60x18 shares = ud(amount);

            FeeInternal memory vars = _getFeeInternal(
                l,
                from,
                shares,
                _getPricePerShareUD60x18()
            );

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
                _updateTimeOfDeposit(l, to, _balanceOf(to), amount);
            }

            emit UpdateQuotes();
        }
    }

    /// @notice Transfers fees to the FEE_RECEIVER.
    function _claimFees(UnderwriterVaultStorage.Layout storage l) internal {
        uint256 claimedFees = l.convertAssetFromUD60x18(l.protocolFees);

        l.protocolFees = ZERO;
        IERC20(_asset()).safeTransfer(FEE_RECEIVER, claimedFees);

        emit ClaimProtocolFees(
            FEE_RECEIVER,
            l.convertAssetToUD60x18(claimedFees)
        );
    }
}
