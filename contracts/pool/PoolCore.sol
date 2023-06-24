// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {ONE, ZERO} from "../libraries/Constants.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";

import {IUserSettings} from "../settings/IUserSettings.sol";

import {IPoolCore} from "./IPoolCore.sol";
import {IPoolInternal} from "./IPoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolCore is IPoolCore, PoolInternal, ReentrancyGuard {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using EnumerableSet for EnumerableSet.UintSet;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using SafeERC20 for IERC20;
    using PRBMathExtra for UD60x18;

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver,
        address referral,
        address settings,
        address vaultRegistry,
        address vxPremia
    ) PoolInternal(factory, router, wrappedNativeToken, feeReceiver, referral, settings, vaultRegistry, vxPremia) {}

    /// @inheritdoc IPoolCore
    function marketPrice() external view returns (UD60x18) {
        return PoolStorage.layout().marketPrice;
    }

    /// @inheritdoc IPoolCore
    function takerFee(
        address taker,
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return
            l.toPoolTokenDecimals(
                _takerFee(taker, size, l.fromPoolTokenDecimals(premium), isPremiumNormalized, l.strike, l.isCallPool)
            );
    }

    /// @inheritdoc IPoolCore
    function _takerFeeLowLevel(
        address taker,
        UD60x18 size,
        UD60x18 premium,
        bool isPremiumNormalized,
        UD60x18 strike,
        bool isCallPool
    ) external view returns (UD60x18) {
        return _takerFee(taker, size, premium, isPremiumNormalized, strike, isCallPool);
    }

    /// @inheritdoc IPoolCore
    function getPoolSettings()
        external
        view
        returns (address base, address quote, address oracleAdapter, UD60x18 strike, uint256 maturity, bool isCallPool)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (l.base, l.quote, l.oracleAdapter, l.strike, l.maturity, l.isCallPool);
    }

    /// @inheritdoc IPoolCore
    function ticks() external view returns (IPoolInternal.TickWithRates[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 longRate = l.longRate;
        UD60x18 shortRate = l.shortRate;
        UD60x18 prev = l.tickIndex.prev(l.currentTick);
        UD60x18 curr = l.currentTick;

        uint256 maxTicks = (ONE / Pricing.MIN_TICK_DISTANCE).unwrap() / 1e18;
        uint256 count;

        IPoolInternal.TickWithRates[] memory _ticks = new IPoolInternal.TickWithRates[](maxTicks);

        // compute the longRate and shortRate at MIN_TICK_PRICE
        if (l.currentTick != Pricing.MIN_TICK_PRICE) {
            while (true) {
                longRate = longRate.add(l.ticks[curr].longDelta);
                shortRate = shortRate.add(l.ticks[curr].shortDelta);

                if (prev == Pricing.MIN_TICK_PRICE) {
                    break;
                }

                curr = prev;
                prev = l.tickIndex.prev(prev);
            }
        }

        prev = Pricing.MIN_TICK_PRICE;
        curr = l.tickIndex.next(Pricing.MIN_TICK_PRICE);

        while (true) {
            _ticks[count++] = IPoolInternal.TickWithRates({
                tick: l.ticks[prev],
                price: prev,
                longRate: longRate,
                shortRate: shortRate
            });

            if (curr == Pricing.MAX_TICK_PRICE) {
                _ticks[count++] = IPoolInternal.TickWithRates({
                    tick: l.ticks[curr],
                    price: curr,
                    longRate: ZERO,
                    shortRate: ZERO
                });
                break;
            }

            prev = curr;

            if (curr <= l.currentTick) {
                longRate = longRate.sub(l.ticks[curr].longDelta);
                shortRate = shortRate.sub(l.ticks[curr].shortDelta);
            } else {
                longRate = longRate.add(l.ticks[curr].longDelta);
                shortRate = shortRate.add(l.ticks[curr].shortDelta);
            }
            curr = l.tickIndex.next(curr);
        }

        // Remove empty elements from array
        if (count < maxTicks) {
            assembly {
                mstore(_ticks, sub(mload(_ticks), sub(maxTicks, count)))
            }
        }

        return _ticks;
    }

    /// @inheritdoc IPoolCore
    function claim(Position.Key calldata p) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _claim(p.toKeyInternal(l.strike, l.isCallPool));
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(Position.Key calldata p) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];
        (UD60x18 pendingClaimableFees, ) = _pendingClaimableFees(l, p.toKeyInternal(l.strike, l.isCallPool), pData);
        return l.toPoolTokenDecimals(pData.claimableFees + pendingClaimableFees);
    }

    /// @inheritdoc IPoolCore
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size,
        address referrer
    ) external nonReentrant {
        return _writeFrom(underwriter, longReceiver, size, referrer);
    }

    /// @inheritdoc IPoolCore
    function annihilate(UD60x18 size) external nonReentrant {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function annihilateFor(address account, UD60x18 size) external nonReentrant {
        _annihilate(account, size);
    }

    /// @inheritdoc IPoolCore
    function exercise() external nonReentrant returns (uint256 exerciseValue) {
        (exerciseValue, ) = _exercise(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function exerciseFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory exerciseValues) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _costPerHolder = l.fromPoolTokenDecimals(costPerHolder);
        exerciseValues = new uint256[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _revertIfActionNotAuthorized(holders[i], IUserSettings.Action.EXERCISE);
                _revertIfCostNotAuthorized(holders[i], _costPerHolder);
            }

            (uint256 exerciseValue, bool success) = _exercise(holders[i], _costPerHolder);
            if (!success) revert Pool__SettlementFailed();
            exerciseValues[i] = exerciseValue;
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, holders.length * costPerHolder);
    }

    /// @inheritdoc IPoolCore
    function settle() external nonReentrant returns (uint256 collateral) {
        (collateral, ) = _settle(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function settleFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory collateral) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _costPerHolder = l.fromPoolTokenDecimals(costPerHolder);
        collateral = new uint256[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _revertIfActionNotAuthorized(holders[i], IUserSettings.Action.SETTLE);
                _revertIfCostNotAuthorized(holders[i], _costPerHolder);
            }

            (uint256 _collateral, bool success) = _settle(holders[i], _costPerHolder);
            if (!success) revert Pool__SettlementFailed();
            collateral[i] = _collateral;
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, holders.length * costPerHolder);
    }

    /// @inheritdoc IPoolCore
    function settlePosition(Position.Key calldata p) external nonReentrant returns (uint256 collateral) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _revertIfOperatorNotAuthorized(p.operator);
        (collateral, ) = _settlePosition(p.toKeyInternal(l.strike, l.isCallPool), ZERO);
    }

    /// @inheritdoc IPoolCore
    function settlePositionFor(
        Position.Key[] calldata p,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory collateral) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _costPerHolder = l.fromPoolTokenDecimals(costPerHolder);
        collateral = new uint256[](p.length);

        for (uint256 i = 0; i < p.length; i++) {
            if (p[i].operator != msg.sender) {
                _revertIfActionNotAuthorized(p[i].operator, IUserSettings.Action.SETTLE_POSITION);
                _revertIfCostNotAuthorized(p[i].operator, _costPerHolder);
            }

            (uint256 _collateral, bool success) = _settlePosition(
                p[i].toKeyInternal(l.strike, l.isCallPool),
                _costPerHolder
            );

            if (!success) revert Pool__SettlementFailed();
            collateral[i] = _collateral;
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, p.length * costPerHolder);
    }

    /// @inheritdoc IPoolCore
    function transferPosition(
        Position.Key calldata srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _revertIfOperatorNotAuthorized(srcP.operator);
        _transferPosition(srcP.toKeyInternal(l.strike, l.isCallPool), newOwner, newOperator, size);
    }

    /// @inheritdoc IPoolCore
    function getSettlementPrice() external view returns (UD60x18) {
        return PoolStorage.layout().settlementPrice;
    }

    /// @inheritdoc IPoolCore
    function getStrandedArea() external view returns (UD60x18 lower, UD60x18 upper) {
        return _getStrandedArea(PoolStorage.layout());
    }

    /// @inheritdoc IPoolCore
    function getTokenIds() external view returns (uint256[] memory) {
        return PoolStorage.layout().tokenIds.toArray();
    }
}
