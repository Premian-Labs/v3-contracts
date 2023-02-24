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
import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";

import "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/volatility/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {IPoolFactory} from "../../factory/IPoolFactory.sol";
import {IPool} from "../../pool/IPool.sol";

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
    using UD60x18 for uint256;
    using SD59x18 for int256;

    uint256 SECONDSINAYEAR = 365 * 24 * 60 * 60;

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

    constructor(address oracleAddress, address factoryAddress) {
        IV_ORACLE_ADDR = oracleAddress;
        FACTORY_ADDR = factoryAddress;
    }

    function setVariable(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().variable = value;
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

    function _getSpotPrice(address oracle) internal view returns (uint256) {
        // TODO: Add spot price validation
        // TODO: change price oracle to oracle adapter
        int256 price = AggregatorInterface(oracle).latestAnswer();
        if (price < 0) revert Vault__ZeroPrice();
        return price.toUint256();
    }

    function _getSpotPrice(
        address oracle,
        uint256 timestamp
    ) internal view returns (uint256) {
        return _getSpotPrice(oracle);
    }

    function _getNumberOfListings() internal view returns (uint256) {
        uint256 n = 0;
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 current = l.minMaturity;

        while (current <= l.maxMaturity) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                n += 1;
            }

            current = l.maturities.next(current);
        }

        return n;
    }

    function _getTotalFairValue() internal view returns (uint256) {
        uint256 spot;
        uint256 strike;
        uint256 timeToMaturity;

        uint256 price;
        uint256 size;

        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 current = l.minMaturity;
        uint256 total = 0;

        // Compute fair value for expired unsettled options
        while (current <= block.timestamp) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                strike = l.maturityToStrikes[current].at(i);

                spot = _getSpotPrice(l.priceOracle, current);

                price = OptionMath.blackScholesPrice(
                    spot,
                    strike,
                    0,
                    1,
                    l.rfRate,
                    l.isCall
                );

                size = l.positionSizes[current][strike];

                total += price.mul(size).div(spot);
            }

            current = l.maturities.next(current);
        }

        // Compute fair value for options that have not expired
        uint256 n = _getNumberOfListings();

        uint256[] memory strikes = new uint256[](n);
        uint256[] memory timeToMaturities = new uint256[](n);
        uint256[] memory maturities = new uint256[](n);

        spot = _getSpotPrice(l.priceOracle);

        while (current <= l.maxMaturity) {
            timeToMaturity = (current - block.timestamp).div(
                365 * 24 * 60 * 60
            );

            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                strikes[i] = l.maturityToStrikes[current].at(i);
                timeToMaturities[i] = timeToMaturity;
                maturities[i] = current;
            }

            current = l.maturities.next(current);
        }

        int256[] memory sigmas = IVolatilityOracle(IV_ORACLE_ADDR)
            .getVolatility(_asset(), spot, strikes, timeToMaturities);

        for (uint256 i; i < sigmas.length; i++) {
            price = OptionMath.blackScholesPrice(
                spot,
                strikes[i],
                timeToMaturities[i],
                uint256(sigmas[i]),
                0,
                l.isCall
            );

            size = l.positionSizes[maturities[i]][strikes[i]];

            total += price.mul(size).div(spot);
        }

        return total;
    }

    function _getTotalLockedSpread() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 last = l.lastMaturity;
        uint256 next = l.maturities.next(last);

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        // TODO: double check handling of negative total locked spread
        uint256 totalLockedSpread = l.totalLockedSpread;

        while (block.timestamp >= next) {
            totalLockedSpread -=
                (next - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;
            spreadUnlockingRate -= l.spreadUnlockingTicks[next];
            lastSpreadUnlockUpdate = next;
            last = next;
            next = l.maturities.next(last);
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

        uint256 last = l.minMaturity;
        uint256 next = l.maturities.next(last);

        uint256 lastSpreadUnlockUpdate = l.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = l.spreadUnlockingRate;
        uint256 totalLockedSpread = l.totalLockedSpread;

        while (block.timestamp >= next) {
            totalLockedSpread -=
                (next - lastSpreadUnlockUpdate) *
                spreadUnlockingRate;
            spreadUnlockingRate -= l.spreadUnlockingTicks[next];
            lastSpreadUnlockUpdate = next;
            last = next;
            next = l.maturities.next(last);
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
    ) internal view virtual override returns (uint256) {
        if (owner == address(0)) {
            revert Vault__AddressZero();
        }
        return _availableAssets();
    }

    function _maxRedeem(
        address owner
    ) internal view virtual override returns (uint256) {
        return _convertToShares(_maxWithdraw(owner));
    }

    function _previewMint(
        uint256 shareAmount
    ) internal view virtual override returns (uint256) {
        return _convertToAssets(shareAmount);
    }

    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual override returns (uint256 shareAmount) {
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

    function _calculateClevel() internal pure returns (uint256) {
        // Utilization rate will be vol global for entire surface
        // TODO: need to calculation utilization of capital
        // TODO: check the last time there was a transaction
        // TODO: return c-level AFTER the impact of the trade
        return 1;
    }

    /// @inheritdoc IUnderwriterVault
    function buy(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        // Get pool address, price and c-level
        (address poolAddr, uint256 price, uint256 cLevel) = quote(
            strike,
            maturity,
            size
        );

        // Add listing
        _addListing(strike, maturity);

        uint256 totalPremium = size * price;

        // TODO: embed the trading fee into the spread (requires calculating fee)
        uint256 spread = 0;

        // Mint option and allocate long token
        IPool(poolAddr).writeFrom(address(this), msg.sender, size);

        // Log trade time stamp for c-level decay
        l.lastTradeTimestamp = block.timestamp;

        uint256 secondsToExpiration = maturity - block.timestamp;
        // Handle the premiums and spread capture generated
        afterBuyStruct memory intel = afterBuyStruct(
            maturity,
            totalPremium,
            secondsToExpiration,
            size,
            spread,
            strike
        );

        _afterBuy(intel);

        return totalPremium;
    }

    function quote(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) public view returns (address, uint256, uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        // Check non Zero Strike
        if (strike == 0) revert Vault__AddressZero();
        // Check valid maturity
        if (block.timestamp >= maturity) revert Vault__OptionExpired();
        // Check if the vault has sufficient funds
        if (size >= _availableAssets()) revert Vault__InsufficientFunds();
        // Compute premium and the spread collected
        uint256 spotPrice = _getSpotPrice(l.priceOracle);

        uint256 secondsToExpiration = maturity - block.timestamp;
        uint256 tau = secondsToExpiration.div(SECONDSINAYEAR);

        int256 sigma = IVolatilityOracle(IV_ORACLE_ADDR).getVolatility(
            _asset(),
            spotPrice,
            strike,
            tau
        );
        uint256 iv = uint256(sigma);

        address poolAddr = _isValidListing(
            spotPrice,
            strike,
            maturity,
            tau,
            iv
        );

        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            strike,
            tau,
            iv,
            l.rfRate,
            l.isCall
        );

        uint256 cLevel = _calculateClevel();

        return (poolAddr, price, cLevel);
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external pure override returns (uint256) {
        //TODO: remove pure when hydrated
        return 0;
    }
}
