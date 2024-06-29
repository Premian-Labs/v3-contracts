// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {IERC1155Receiver} from "@solidstate/contracts/interfaces/IERC1155Receiver.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ERC4626BaseInternal} from "@solidstate/contracts/token/ERC4626/base/ERC4626BaseInternal.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {IOwnable} from "@solidstate/contracts/access/ownable/IOwnable.sol";

import {IOracleAdapter} from "../../../adapter/IOracleAdapter.sol";
import {IPoolFactory} from "../../../factory/IPoolFactory.sol";
import {ZERO, ONE, WAD, ONE_HOUR, ONE_YEAR} from "../../../libraries/Constants.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../libraries/EnumerableSetUD60x18.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";
import {OptionMathExternal} from "../../../libraries/OptionMathExternal.sol";
import {PRBMathExtra} from "../../../libraries/PRBMathExtra.sol";
import {IVolatilityOracle} from "../../../oracle/IVolatilityOracle.sol";
import {IPool} from "../../../pool/IPool.sol";
import {PoolStorage} from "../../../pool/PoolStorage.sol";

import {IUnderwriterVault, IVault} from "./IUnderwriterVault.sol";
import {Vault} from "../../Vault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";

/// @title An ERC-4626 implementation for underwriting call/put option contracts by using collateral deposited by users
contract UnderwriterVault is IUnderwriterVault, Vault, ReentrancyGuard {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;

    address internal immutable VAULT_REGISTRY;
    address internal immutable FEE_RECEIVER;
    address internal immutable IV_ORACLE;
    address internal immutable FACTORY;
    address internal immutable ROUTER;
    address internal immutable VX_PREMIA;
    address internal immutable POOL_DIAMOND;

    constructor(
        address vaultRegistry,
        address feeReceiver,
        address oracle,
        address factory,
        address router,
        address vxPremia,
        address poolDiamond,
        address vaultMining
    ) Vault(vaultMining) {
        VAULT_REGISTRY = vaultRegistry;
        FEE_RECEIVER = feeReceiver;
        IV_ORACLE = oracle;
        FACTORY = factory;
        ROUTER = router;
        VX_PREMIA = vxPremia;
        POOL_DIAMOND = poolDiamond;
    }

    /// @inheritdoc IVault
    function getUtilisation() public view override(IVault, Vault) returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        (
            UD60x18 totalAssetsAfterSettlement,
            UD60x18 totalLockedAfterSettlement
        ) = _computeAssetsAfterSettlementOfExpiredOptions(l);

        UD60x18 totalAssets = totalAssetsAfterSettlement + l.fromTokenDecimals(l.pendingAssetsDeposit);
        if (totalAssets == ZERO) return ZERO;

        return totalLockedAfterSettlement / totalAssets;
    }

    /// @inheritdoc IVault
    function updateSettings(bytes memory settings) external {
        _revertIfNotRegistryOwner(msg.sender);

        // Decode data and update storage variable
        UnderwriterVaultStorage.layout().updateSettings(settings);

        emit UpdateSettings(settings);
    }

    /// @inheritdoc IVault
    function getSettings() external view returns (bytes memory) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        UD60x18[] memory settings = new UD60x18[](11);

        settings[0] = l.alphaCLevel;
        settings[1] = l.hourlyDecayDiscount;
        settings[2] = l.minCLevel;
        settings[3] = l.maxCLevel;
        settings[4] = l.minDTE;
        settings[5] = l.maxDTE;
        settings[6] = l.minDelta;
        settings[7] = l.maxDelta;
        settings[8] = l.performanceFeeRate;
        settings[9] = l.managementFeeRate;
        settings[10] = l.enableSell ? ud(1) : ud(0);

        return abi.encode(settings);
    }

    /// @notice Gets the timestamp of the current block.
    /// @dev We are using a virtual internal function to be able to override in Mock contract for testing purpose
    function _getBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view override returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        return l.toTokenDecimals(l.totalAssets);
    }

    /// @notice Gets the spot price at the current time
    /// @return The spot price at the current time
    function _getSpotPrice() internal view virtual returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        return IOracleAdapter(l.oracleAdapter).getPrice(l.base, l.quote);
    }

    /// @notice Gets the total liabilities value of the basket of unexpired
    ///         options underwritten by this vault at the current time
    /// @return The the total liabilities of the basket of unexpired options underwritten
    function _getTotalLiabilitiesUnexpired(UnderwriterVaultStorage.Layout storage l) internal view returns (UD60x18) {
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

        {
            uint256 i = 0;
            while (current <= l.maxMaturity && current != 0) {
                for (uint256 j = 0; j < l.maturityToStrikes[current].length(); j++) {
                    vars.strikes[i] = l.maturityToStrikes[current].at(j);
                    vars.timeToMaturities[i] = ud((current - timestamp) * WAD) / ud(ONE_YEAR * WAD);
                    vars.maturities[i] = current;
                    i++;
                }

                current = l.maturities.next(current);
            }
        }

        vars.sigmas = IVolatilityOracle(IV_ORACLE).getVolatility(
            l.base,
            vars.spot,
            vars.strikes,
            vars.timeToMaturities
        );

        for (uint256 k = 0; k < n; k++) {
            UD60x18 price = OptionMathExternal.blackScholesPrice(
                vars.spot,
                vars.strikes[k],
                vars.timeToMaturities[k],
                vars.sigmas[k],
                vars.riskFreeRate,
                l.isCall
            );
            total = total + price * l.positionSizes[vars.maturities[k]][vars.strikes[k]];
        }

        return l.isCall ? total / vars.spot : total;
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

            vars.spreadUnlockingRate = vars.spreadUnlockingRate - l.spreadUnlockingTicks[current];
            vars.lastSpreadUnlockUpdate = current;
            current = l.maturities.next(current);
        }

        vars.totalLockedSpread =
            vars.totalLockedSpread -
            ud((timestamp - vars.lastSpreadUnlockUpdate) * WAD) *
            vars.spreadUnlockingRate;
        vars.lastSpreadUnlockUpdate = timestamp;
    }

    /// @dev _balanceOf returns the balance of the ERC20 share token which is always in 18 decimal places,
    ///      therefore no further scaling has to be applied
    function _balanceOfUD60x18(address owner) internal view returns (UD60x18) {
        return ud(_balanceOf(owner));
    }

    function _totalSupplyUD60x18() internal view returns (UD60x18) {
        return ud(_totalSupply());
    }

    /// @notice Gets the amount of available assets that are available after settlement
    /// @return The amount of available assets after calling the settle function
    function _availableAssetsUD60x18(UnderwriterVaultStorage.Layout storage l) internal view returns (UD60x18) {
        (
            UD60x18 totalAssetsAfterSettlement,
            UD60x18 totalLockedAfterSettlement
        ) = _computeAssetsAfterSettlementOfExpiredOptions(l);
        return totalAssetsAfterSettlement - totalLockedAfterSettlement - _getLockedSpreadInternal(l).totalLockedSpread;
    }

    /// @notice Gets the current price per share for the vault
    /// @return The current price per share
    function _getPricePerShareUD60x18() internal view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        if ((_totalSupplyUD60x18() != ZERO) && (l.totalAssets != ZERO)) {
            (UD60x18 totalAssetsPostSettlement, ) = _computeAssetsAfterSettlementOfExpiredOptions(l);
            UD60x18 managementFeeInShares = _computeManagementFee(l, _getBlockTimestamp());
            UD60x18 totalAssets = totalAssetsPostSettlement -
                _getLockedSpreadInternal(l).totalLockedSpread -
                _getTotalLiabilitiesUnexpired(l);
            return totalAssets / (_totalSupplyUD60x18() + managementFeeInShares);
        }

        return ONE;
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

    function _convertToSharesUD60x18(UD60x18 assetAmount, UD60x18 pps) internal view returns (UD60x18 shareAmount) {
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
    function _convertToShares(uint256 assetAmount) internal view override returns (uint256 shareAmount) {
        return
            _convertToSharesUD60x18(
                UnderwriterVaultStorage.layout().fromTokenDecimals(assetAmount),
                _getPricePerShareUD60x18()
            ).unwrap();
    }

    function _convertToAssetsUD60x18(UD60x18 shareAmount, UD60x18 pps) internal view returns (UD60x18 assetAmount) {
        _revertIfZeroShares(_totalSupplyUD60x18().unwrap());

        assetAmount = shareAmount * pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(uint256 shareAmount) internal view virtual override returns (uint256 assetAmount) {
        UD60x18 assets = _convertToAssetsUD60x18(ud(shareAmount), _getPricePerShareUD60x18());
        assetAmount = UnderwriterVaultStorage.layout().toTokenDecimals(assets);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _deposit(
        address caller,
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 assetAmountOffset,
        uint256 shareAmountOffset
    ) internal virtual override {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        l.pendingAssetsDeposit = assetAmount;
        super._deposit(caller, receiver, assetAmount, shareAmount, assetAmountOffset, shareAmountOffset);
        if (l.pendingAssetsDeposit != assetAmount) revert Vault__InvariantViolated(); // Safety check, should never happen
        delete l.pendingAssetsDeposit;

        emit PricePerShare(l.fromTokenDecimals(assetAmount) / ud(shareAmount));
    }

    /// @inheritdoc ERC4626BaseInternal
    function _deposit(
        uint256 assetAmount,
        address receiver
    ) internal virtual override nonReentrant returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Note: vault must settle expired options before pps is calculated
        _settle(l);
        // charge management fees such that the timestamp is up to date
        _chargeManagementFees();
        shareAmount = super._deposit(assetAmount, receiver);
    }

    function _previewMintUD60x18(UD60x18 shareAmount) internal view returns (UD60x18 assetAmount) {
        assetAmount = _totalSupplyUD60x18() == ZERO ? shareAmount : shareAmount * _getPricePerShareUD60x18();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewMint(uint256 shareAmount) internal view virtual override returns (uint256 assetAmount) {
        UD60x18 assets = _previewMintUD60x18(ud(shareAmount));
        assetAmount = UnderwriterVaultStorage.layout().toTokenDecimals(assets);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _mint(
        uint256 shareAmount,
        address receiver
    ) internal virtual override nonReentrant returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Note: vault must settle expired options before pps is calculated
        _settle(l);
        // charge management fees such that the timestamp is up to date
        _chargeManagementFees();
        return super._mint(shareAmount, receiver);
    }

    function _maxRedeemUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        _revertIfAddressZero(owner);

        return _maxWithdrawUD60x18(l, owner, pps) / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(address owner) internal view virtual override returns (uint256) {
        return _maxRedeemUD60x18(UnderwriterVaultStorage.layout(), owner, _getPricePerShareUD60x18()).unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) internal virtual override nonReentrant returns (uint256 assetAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Note: vault must settle expired options before pps is calculated
        _settle(l);
        // charge management fees such that vault share holder pays management fees due
        _chargeManagementFees();

        UD60x18 shares = ud(shareAmount);
        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 maxRedeem = _maxRedeemUD60x18(l, owner, pps);

        _revertIfMaximumAmountExceeded(maxRedeem, shares);

        assetAmount = l.toTokenDecimals(shares * pps);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);

        emit PricePerShare(pps);
    }

    function _maxWithdrawUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        address owner,
        UD60x18 pps
    ) internal view returns (UD60x18 withdrawableAssets) {
        _revertIfAddressZero(owner);

        UD60x18 assetsOwner = _balanceOfUD60x18(owner) * pps;
        UD60x18 availableAssets = _availableAssetsUD60x18(l);

        withdrawableAssets = assetsOwner > availableAssets ? availableAssets : assetsOwner;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxWithdraw(address owner) internal view virtual override returns (uint256 withdrawableAssets) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        withdrawableAssets = l.toTokenDecimals(_maxWithdrawUD60x18(l, owner, _getPricePerShareUD60x18()));
    }

    function _previewWithdrawUD60x18(
        UnderwriterVaultStorage.Layout storage l,
        UD60x18 assetAmount,
        UD60x18 pps
    ) internal view returns (UD60x18 shareAmount) {
        _revertIfZeroShares(_totalSupplyUD60x18().unwrap());
        if (_availableAssetsUD60x18(l) == ZERO) revert Vault__InsufficientFunds();
        shareAmount = assetAmount / pps;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(uint256 assetAmount) internal view virtual override returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        shareAmount = _previewWithdrawUD60x18(l, l.fromTokenDecimals(assetAmount), _getPricePerShareUD60x18()).unwrap();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    ) internal virtual override nonReentrant returns (uint256 shareAmount) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Note: vault must settle expired options before pps is calculated
        _settle(l);
        // charge management fees such that vault share holder pays management fees due
        _chargeManagementFees();

        UD60x18 assets = l.fromTokenDecimals(assetAmount);
        UD60x18 pps = _getPricePerShareUD60x18();
        UD60x18 maxWithdraw = _maxWithdrawUD60x18(l, owner, pps);

        _revertIfMaximumAmountExceeded(maxWithdraw, assets);

        shareAmount = _previewWithdrawUD60x18(l, assets, pps).unwrap();

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);

        emit PricePerShare(pps);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _afterDeposit(address receiver, uint256 assetAmount, uint256 shareAmount) internal virtual override {
        _revertIfAddressZero(receiver);
        _revertIfZeroAsset(assetAmount);
        _revertIfZeroShares(shareAmount);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        // Add assetAmount deposited to user's balance
        // This is needed to compute average price per share
        l.totalAssets = l.totalAssets + l.fromTokenDecimals(assetAmount);

        emit UpdateQuotes();
    }

    /// @inheritdoc ERC4626BaseInternal
    function _beforeWithdraw(address owner, uint256 assetAmount, uint256 shareAmount) internal virtual override {
        _revertIfAddressZero(owner);
        _revertIfZeroAsset(assetAmount);
        _revertIfZeroShares(shareAmount);

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        // Remove the assets from totalAssets
        l.totalAssets = l.totalAssets - l.fromTokenDecimals(assetAmount);

        emit UpdateQuotes();
    }

    /// @notice An internal hook inside the trade function that is called after
    ///         logic inside the trade function is run to update state variables
    /// @param isBuy Whether this is a buy or a sell
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    /// @param size The amount of contracts.
    /// @param spread The spread added on to the premium due to C-level
    /// @param premium The base premium that is charged
    function _afterTrade(
        UnderwriterVaultStorage.Layout storage l,
        bool isBuy,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size,
        UD60x18 spread,
        UD60x18 premium
    ) internal {
        // spread state needs to be updated otherwise spread dispersion is inconsistent
        _updateState(l);

        UD60x18 spreadProtocol = l.truncate(spread * l.performanceFeeRate);
        UD60x18 spreadLP = spread - spreadProtocol;

        UD60x18 spreadRateLP = spreadLP / ud((maturity - _getBlockTimestamp()) * WAD);
        UD60x18 collateral = l.collateral(size, strike);

        l.spreadUnlockingRate = l.spreadUnlockingRate + spreadRateLP;
        l.spreadUnlockingTicks[maturity] = l.spreadUnlockingTicks[maturity] + spreadRateLP;
        l.totalLockedSpread = l.totalLockedSpread + spreadLP;

        if (isBuy) {
            l.totalAssets = l.totalAssets + premium + spreadLP;
            l.totalLockedAssets = l.totalLockedAssets + collateral;

            // Updated weighted average for premiums
            UD60x18 avgPremium = l.avgPremium[maturity][strike];
            l.avgPremium[maturity][strike] =
                (avgPremium * l.positionSizes[maturity][strike] + premium) /
                (l.positionSizes[maturity][strike] + size);
            l.positionSizes[maturity][strike] = l.positionSizes[maturity][strike] + size;
        } else {
            l.totalAssets = l.totalAssets - (premium - spreadLP);
            l.totalLockedAssets = l.totalLockedAssets - collateral;

            l.positionSizes[maturity][strike] = l.positionSizes[maturity][strike] - size;
        }

        // Update the timestamp of latest trade
        l.lastTradeTimestamp = _getBlockTimestamp();

        // we cannot mint new shares as we did for management fees as this would require computing the fair value of the options which would be inefficient.
        l.protocolFees = l.protocolFees + spreadProtocol;

        if (spreadProtocol > ZERO) emit PerformanceFeePaid(FEE_RECEIVER, l.toTokenDecimals(spreadProtocol));
    }

    /// @notice Gets the pool address corresponding to the given strike and maturity. Returns zero address if pool is not deployed.
    /// @param strike The strike price for the pool
    /// @param maturity The maturity for the pool
    /// @return The pool address (zero address if pool is not deployed)
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

        (address pool, bool isDeployed) = IPoolFactory(FACTORY).getPoolAddress(_poolKey);

        return isDeployed ? pool : address(0);
    }

    /// @notice Computes the `totalAssets` and `totalLockedAssets` after the settlement of expired options.
    ///         The `totalAssets` after settlement are the `totalAssets` less the exercise value of the call or put
    ///         options that were sold. The `totalLockedAssets` after settlement are the `totalLockedAssets` less
    ///         the collateral unlocked by the call or put.
    /// @return totalAssets the total assets post settlement
    /// @return totalLockedAssets the total locked assets post settlement
    function _computeAssetsAfterSettlementOfExpiredOptions(
        UnderwriterVaultStorage.Layout storage l
    ) internal view returns (UD60x18 totalAssets, UD60x18 totalLockedAssets) {
        uint256 timestamp = _getBlockTimestamp();

        // Get last maturity before the next block timestamp
        uint256 lastExpired = timestamp >= l.maxMaturity
            ? l.maxMaturity
            : l.maturities.prev(l.getMaturityAfterTimestamp(timestamp));

        uint256 current = l.minMaturity;
        totalAssets = l.totalAssets;
        totalLockedAssets = l.totalLockedAssets;

        while (current <= lastExpired && current != 0) {
            for (uint256 i = 0; i < l.maturityToStrikes[current].length(); i++) {
                UD60x18 strike = l.maturityToStrikes[current].at(i);
                UD60x18 positionSize = l.positionSizes[current][strike];
                UD60x18 unlockedCollateral = l.isCall ? positionSize : positionSize * strike;

                totalLockedAssets = totalLockedAssets - unlockedCollateral;

                // Get the settlement price from oracle
                UD60x18 settlementPrice = IOracleAdapter(l.oracleAdapter).getPriceAt(l.base, l.quote, current);

                UD60x18 callPayoff = l.isCall
                    ? OptionMath.relu(settlementPrice.intoSD59x18() - strike.intoSD59x18()) / settlementPrice
                    : OptionMath.relu(strike.intoSD59x18() - settlementPrice.intoSD59x18());
                totalAssets = totalAssets - positionSize * callPayoff;
            }
            current = l.maturities.next(current);
        }
        return (totalAssets, totalLockedAssets);
    }

    /// @notice Get the variables needed in order to compute the quote for a trade
    function _getQuoteInternal(
        UnderwriterVaultStorage.Layout storage l,
        QuoteArgsInternal memory args,
        bool revertIfPoolNotDeployed
    ) internal view returns (QuoteInternal memory quote) {
        _revertIfZeroSize(args.size);
        _revertIfNotTradeableWithVault(l.isCall, args.isCall);
        _revertIfOptionInvalid(args.strike, args.maturity);

        QuoteVars memory vars;

        if (args.isBuy) {
            (UD60x18 totalAssets, UD60x18 totalLockedAssets) = _computeAssetsAfterSettlementOfExpiredOptions(l);

            _revertIfInsufficientFunds(
                args.strike,
                args.size,
                totalAssets - totalLockedAssets - _getLockedSpreadInternal(l).totalLockedSpread
            );

            // Compute C-level

            // If utilisation is a function of premium, and we want to use that to compute the premium we get an
            // implicit equation. For this function, there is no explicit solution enabling us to include premiums.
            // Therefore, this is the current approximation we are using.
            UD60x18 utilisationAfter = (totalLockedAssets + l.collateral(args.size, args.strike)) / totalAssets;

            vars.cLevel = OptionMathExternal.computeCLevelGeoMean({
                utilisationBefore: totalLockedAssets / totalAssets,
                utilisationAfter: utilisationAfter,
                duration: ud((_getBlockTimestamp() - l.lastTradeTimestamp) * WAD) / ud(ONE_HOUR * WAD),
                alpha: l.alphaCLevel,
                minCLevel: l.minCLevel,
                maxCLevel: l.maxCLevel,
                decayRate: l.hourlyDecayDiscount
            });
        } else {
            _revertIfInsufficientShorts(l, args.maturity, args.strike, args.size);
            _revertIfSellIsDisabled(l.enableSell);
            vars.cLevel = ONE;
        }

        vars.spot = _getSpotPrice();

        vars.tau = ud((args.maturity - _getBlockTimestamp()) * WAD) / ud(ONE_YEAR * WAD);

        // Compute time until maturity and check bounds
        if (args.isBuy) _revertIfOutOfDTEBounds(vars.tau * ud(365 * WAD), l.minDTE, l.maxDTE);

        vars.sigma = IVolatilityOracle(IV_ORACLE).getVolatility(l.base, vars.spot, args.strike, vars.tau);
        vars.riskFreeRate = IVolatilityOracle(IV_ORACLE).getRiskFreeRate();

        if (args.isBuy) {
            // Compute delta and check bounds
            vars.delta = OptionMathExternal
                .optionDelta(vars.spot, args.strike, vars.tau, vars.sigma, vars.riskFreeRate, l.isCall)
                .abs();
            _revertIfOutOfDeltaBounds(vars.delta.intoUD60x18(), l.minDelta, l.maxDelta);
        }

        vars.price = OptionMathExternal.blackScholesPrice(
            vars.spot,
            args.strike,
            vars.tau,
            vars.sigma,
            vars.riskFreeRate,
            l.isCall
        );

        vars.price = l.isCall ? vars.price / vars.spot : vars.price;
        // Compute output variables
        quote.premium = vars.price * args.size;
        quote.premium = l.truncate(quote.premium); // Round down to align with token

        // If buy-to-close, then use avg premium as upper bound for how much we will pay
        // If fair value, is cheaper then use that
        quote.spread = args.isBuy
            ? (vars.cLevel - ONE) * quote.premium
            : (vars.price - PRBMathExtra.min(l.avgPremium[args.maturity][args.strike], vars.price)) * args.size;

        quote.spread = l.truncate(quote.spread); // Round down to align with token
        quote.pool = _getPoolAddress(l, args.strike, args.maturity);

        if (revertIfPoolNotDeployed && quote.pool == address(0)) revert Vault__OptionPoolNotListed();

        // This is to deal with the scenario where user request a quote for a pool not yet deployed
        // Instead of calling `takerFee` on the pool, we call `_takerFeeLowLevel` directly on `POOL_DIAMOND`.
        // This function doesnt require any data from pool storage and therefore will succeed even if pool is not deployed yet.
        // This only applies in buy case (sell case we already have the shorts no minting necessary)
        if (args.isBuy)
            quote.mintingFee = IPool(POOL_DIAMOND)._takerFeeLowLevel(
                args.taker,
                args.size,
                ZERO,
                true,
                false,
                args.strike,
                l.isCall
            );
    }

    /// @notice Truncates the trade size (18 decimals) by the number of significant digits in the strike price
    function _truncateTradeSize(UD60x18 size, UD60x18 strike) internal pure returns (UD60x18) {
        return OptionMath.truncate(size, 18 - OptionMath.countSignificantDigits(strike));
    }

    /// @inheritdoc IVault
    function getQuote(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy,
        address taker
    ) external view returns (uint256 premium) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Truncate the size to mitigate the risk of possible rounding errors accumulating in the system
        size = _truncateTradeSize(size, poolKey.strike);

        QuoteInternal memory quote = _getQuoteInternal(
            l,
            QuoteArgsInternal({
                strike: poolKey.strike,
                maturity: poolKey.maturity,
                isCall: poolKey.isCallPool,
                size: size,
                isBuy: isBuy,
                taker: taker
            }),
            false
        );

        premium = UnderwriterVaultStorage.layout().toTokenDecimals(
            isBuy ? quote.premium + quote.spread + quote.mintingFee : quote.premium - quote.spread
        );
    }

    /// @inheritdoc IVault
    function trade(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        address referrer
    ) external override nonReentrant {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();
        // Truncate the size to mitigate the risk of possible rounding errors accumulating in the system
        size = _truncateTradeSize(size, poolKey.strike);

        // Note: vault must settle expired options before pps is calculated
        _settle(l);

        QuoteInternal memory quote = _getQuoteInternal(
            l,
            QuoteArgsInternal({
                strike: poolKey.strike,
                maturity: poolKey.maturity,
                isCall: poolKey.isCallPool,
                size: size,
                isBuy: isBuy,
                taker: msg.sender
            }),
            true
        );

        UD60x18 totalPremium = (isBuy) ? quote.premium + quote.spread + quote.mintingFee : quote.premium - quote.spread;

        _revertIfAboveTradeMaxSlippage(totalPremium, l.fromTokenDecimals(premiumLimit), isBuy);

        if (isBuy) {
            // Add listing
            l.addListing(poolKey.strike, poolKey.maturity);

            // Collect option premium from buyer
            IERC20(_asset()).safeTransferFrom(msg.sender, address(this), l.toTokenDecimals(totalPremium));

            // Approve transfer of base / quote token
            uint256 approveAmountScaled = l.toTokenDecimals(l.collateral(size, poolKey.strike) + quote.mintingFee);

            IERC20(_asset()).approve(ROUTER, approveAmountScaled);

            // Mint option and allocate long token
            IPool(quote.pool).writeFrom(address(this), msg.sender, size, referrer);

            // Annihilate shorts and longs for user
            UD60x18 shorts = ud(IPool(quote.pool).balanceOf(msg.sender, PoolStorage.SHORT));
            UD60x18 longs = ud(IPool(quote.pool).balanceOf(msg.sender, PoolStorage.LONG));
            UD60x18 annihilateSize = PRBMathExtra.min(shorts, longs);
            if (annihilateSize > ZERO) IPool(quote.pool).annihilateFor(msg.sender, annihilateSize);
        } else {
            UD60x18 annihilateSize = PRBMathExtra.min(
                size,
                ud(IPool(quote.pool).balanceOf(msg.sender, PoolStorage.LONG))
            );

            // Trader: Sell-To-Close, Vault: Buy-To-Close
            if (annihilateSize > ZERO) {
                // Transfer long positions from user to the vault
                IPool(quote.pool).safeTransferFrom(
                    msg.sender,
                    address(this),
                    PoolStorage.LONG,
                    annihilateSize.unwrap(),
                    ""
                );
                IPool(quote.pool).annihilate(annihilateSize);
            }

            UD60x18 collateral = l.collateral(size - annihilateSize, poolKey.strike);
            if (totalPremium > collateral) {
                // Transfer to the user if the required collateral is less than the premiums
                IERC20(_asset()).safeTransfer(msg.sender, l.toTokenDecimals(totalPremium - collateral));
                // Transfer the collateral from the user if the required funds is greater than the
                // premiums are receiving.
            } else {
                IERC20(_asset()).safeTransferFrom(
                    msg.sender,
                    address(this),
                    l.toTokenDecimals(collateral - totalPremium)
                );
            }
            // Transfer collateral from user (if required) then send them the short contracts
            // Trader: Sell-To-Open, Vault: Buy-To-Close
            if (size - annihilateSize > ZERO) {
                // Transfer short positions to the user
                IPool(quote.pool).safeTransferFrom(
                    address(this),
                    msg.sender,
                    PoolStorage.SHORT,
                    (size - annihilateSize).unwrap(),
                    ""
                );
            }
        }

        // Handle the premiums and spread capture generated
        _afterTrade(l, isBuy, poolKey.strike, poolKey.maturity, size, quote.spread, quote.premium);

        // Emit trade event
        emit Trade(msg.sender, quote.pool, size, isBuy, totalPremium, quote.mintingFee, ZERO, quote.spread);

        // Emit event for updated quotes
        emit UpdateQuotes();
    }

    /// @notice Settles all options that are on a single maturity
    /// @param maturity The maturity that options will be settled for
    function _settleMaturity(UnderwriterVaultStorage.Layout storage l, uint256 maturity) internal {
        for (uint256 i = 0; i < l.maturityToStrikes[maturity].length(); i++) {
            UD60x18 strike = l.maturityToStrikes[maturity].at(i);
            UD60x18 positionSize = l.positionSizes[maturity][strike];
            UD60x18 unlockedCollateral = l.isCall ? positionSize : positionSize * strike;
            // TODO: remove after settling trades
            if (unlockedCollateral > l.totalLockedAssets) l.totalLockedAssets = unlockedCollateral;
            l.totalLockedAssets = l.totalLockedAssets - unlockedCollateral;
            address pool = _getPoolAddress(l, strike, maturity);
            UD60x18 collateralValue = l.fromTokenDecimals(IPool(pool).settle());
            l.totalAssets = l.totalAssets - (unlockedCollateral - collateralValue);

            emit Settle(pool, positionSize, ZERO);
        }
    }

    /// @notice Settles all options that are expired
    function _settle(UnderwriterVaultStorage.Layout storage l) internal {
        // Needs to update state as settle effects the listed positions, i.e. maturities and maturityToStrikes.
        _updateState(l);

        uint256 timestamp = _getBlockTimestamp();

        // Get last maturity before the next block timestamp
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

        _claimFees(l);

        emit UpdateQuotes();
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external override nonReentrant {
        _settle(UnderwriterVaultStorage.layout());
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    /// @notice Computes and returns the management fee in shares that have to be paid by vault share holders for using the vault.
    /// @param l Contains stored parameters of the vault, including the managementFeeRate and the lastManagementFeeTimestamp
    /// @param timestamp The block's current timestamp.
    /// @return managementFeeInShares Returns the amount due in management fees in terms of shares (18 decimals).
    function _computeManagementFee(
        UnderwriterVaultStorage.Layout storage l,
        uint256 timestamp
    ) internal view returns (UD60x18 managementFeeInShares) {
        if (l.totalAssets == ZERO) {
            managementFeeInShares = ZERO;
        } else {
            UD60x18 timeSinceLastDeposit = ud((timestamp - l.lastManagementFeeTimestamp) * WAD) / ud(ONE_YEAR * WAD);
            // gamma is the percentage we charge in management fees from the totalAssets resulting in the new pps
            // newPPS = A * (1 - gamma) / S = A / ( S * ( 1 / (1 - gamma) )
            // from this we can compute the shares that need to be minted
            // sharesToMint = S * (1 / (1 - gamma)) - S = S * gamma / (1 - gamma)
            UD60x18 gamma = l.managementFeeRate * timeSinceLastDeposit;
            managementFeeInShares = _totalSupplyUD60x18() * (gamma / (ONE - gamma));
        }
    }

    /// @notice Charges the management fees from by liquidity providers.
    function _chargeManagementFees() internal {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        uint256 timestamp = _getBlockTimestamp();
        if (timestamp == l.lastManagementFeeTimestamp) return;

        // if there are no totalAssets we won't charge management fees
        if (l.totalAssets > ZERO) {
            UD60x18 managementFeeInShares = _computeManagementFee(l, timestamp);
            _mint(FEE_RECEIVER, managementFeeInShares.unwrap());
            emit ManagementFeePaid(FEE_RECEIVER, managementFeeInShares.unwrap());
        }

        l.lastManagementFeeTimestamp = timestamp;
    }

    /// @notice Transfers fees to the FEE_RECEIVER.
    function _claimFees(UnderwriterVaultStorage.Layout storage l) internal {
        uint256 claimedFees = l.toTokenDecimals(l.protocolFees);

        if (claimedFees == 0) return;

        l.protocolFees = ZERO;
        IERC20(_asset()).safeTransfer(FEE_RECEIVER, claimedFees);
        emit ClaimProtocolFees(FEE_RECEIVER, claimedFees);
    }

    function _revertIfNotRegistryOwner(address addr) internal view {
        if (addr != IOwnable(VAULT_REGISTRY).owner()) revert Vault__NotAuthorized();
    }

    /// @notice Ensures that an option is tradeable with the vault.
    /// @param size The amount of contracts
    function _revertIfZeroSize(UD60x18 size) internal pure {
        if (size == ZERO) revert Vault__ZeroSize();
    }

    /// @notice Ensures that a share amount is non zero.
    /// @param shares The amount of shares
    function _revertIfZeroShares(uint256 shares) internal pure {
        if (shares == 0) revert Vault__ZeroShares();
    }

    /// @notice Ensures that an asset amount is non zero.
    /// @param amount The amount of assets
    function _revertIfZeroAsset(uint256 amount) internal pure {
        if (amount == 0) revert Vault__ZeroAsset();
    }

    /// @notice Ensures that an address is non zero.
    /// @param addr The address to check
    function _revertIfAddressZero(address addr) internal pure {
        if (addr == address(0)) revert Vault__AddressZero();
    }

    /// @notice Ensures that an amount is not above maximum
    /// @param maximum The maximum amount
    /// @param amount The amount to check
    function _revertIfMaximumAmountExceeded(UD60x18 maximum, UD60x18 amount) internal pure {
        if (amount > maximum) revert Vault__MaximumAmountExceeded(maximum, amount);
    }

    /// @notice Ensures that an option is tradeable with the vault.
    /// @param isCallVault Whether the vault is a call or put vault.
    /// @param isCallOption Whether the option is a call or put.
    function _revertIfNotTradeableWithVault(bool isCallVault, bool isCallOption) internal pure {
        if (isCallOption != isCallVault) revert Vault__OptionTypeMismatchWithVault();
    }

    /// @notice Ensures that an option is valid for trading.
    /// @param strike The strike price of the option.
    /// @param maturity The maturity of the option.
    function _revertIfOptionInvalid(UD60x18 strike, uint256 maturity) internal view {
        // Check non Zero Strike
        if (strike == ZERO) revert Vault__StrikeZero();
        // Check valid maturity
        if (_getBlockTimestamp() >= maturity) revert Vault__OptionExpired(_getBlockTimestamp(), maturity);
    }

    /// @notice Ensures there is sufficient funds for processing a trade.
    /// @param strike The strike price.
    /// @param size The amount of contracts.
    /// @param availableAssets The amount of available assets currently in the vault.
    function _revertIfInsufficientFunds(UD60x18 strike, UD60x18 size, UD60x18 availableAssets) internal view {
        // Check if the vault has sufficient funds
        if (UnderwriterVaultStorage.layout().collateral(size, strike) >= availableAssets)
            revert Vault__InsufficientFunds();
    }

    /// @notice Ensures that a value is within the DTE bounds.
    /// @param value The observed value of the variable.
    /// @param minimum The minimum value the variable can be.
    /// @param maximum The maximum value the variable can be.
    function _revertIfOutOfDTEBounds(UD60x18 value, UD60x18 minimum, UD60x18 maximum) internal pure {
        if (value < minimum || value > maximum) revert Vault__OutOfDTEBounds();
    }

    /// @notice Ensures that a value is within the delta bounds.
    /// @param value The observed value of the variable.
    /// @param minimum The minimum value the variable can be.
    /// @param maximum The maximum value the variable can be.
    function _revertIfOutOfDeltaBounds(UD60x18 value, UD60x18 minimum, UD60x18 maximum) internal pure {
        if (value < minimum || value > maximum) revert Vault__OutOfDeltaBounds();
    }

    /// @notice Ensures that a value is within the delta bounds.
    /// @param totalPremium The total premium of the trade
    /// @param premiumLimit The premium limit of the trade
    /// @param isBuy Whether the trade is a buy or a sell.
    function _revertIfAboveTradeMaxSlippage(UD60x18 totalPremium, UD60x18 premiumLimit, bool isBuy) internal pure {
        if (isBuy && totalPremium > premiumLimit) revert Vault__AboveMaxSlippage(totalPremium, premiumLimit);
        if (!isBuy && totalPremium < premiumLimit) revert Vault__AboveMaxSlippage(totalPremium, premiumLimit);
    }

    /// @notice Ensures there is sufficient shorts for processing a sell trade.
    /// @param maturity The maturity.
    /// @param strike The strike price.
    /// @param size The amount of contracts.
    function _revertIfInsufficientShorts(
        UnderwriterVaultStorage.Layout storage l,
        uint256 maturity,
        UD60x18 strike,
        UD60x18 size
    ) internal view {
        if (l.positionSizes[maturity][strike] < size) revert Vault__InsufficientShorts();
    }

    /// @notice Ensures that the vault can't buy-to-close unless it is enabled.
    /// @param enableSell Whether sell is enabled or not.
    function _revertIfSellIsDisabled(bool enableSell) internal pure {
        if (!enableSell) revert Vault__SellDisabled();
    }
}
