// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {IPoolInternal} from "./IPoolInternal.sol";
import {PoolInternal} from "./PoolInternal.sol";

import {ONE, ZERO} from "../libraries/Constants.sol";
import {Pricing} from "../libraries/Pricing.sol";
import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";

import {IPoolCore} from "./IPoolCore.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolCore is IPoolCore, PoolInternal, ReentrancyGuard {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
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
        return l.toPoolTokenDecimals(_takerFee(l, taker, size, l.fromPoolTokenDecimals(premium), isPremiumNormalized));
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
    function tick(UD60x18 price) external view returns (IPoolInternal.TickWithLiquidity memory) {
        IPoolInternal.Tick memory _tick = PoolStorage.layout().ticks[price];

        return
            IPoolInternal.TickWithLiquidity({
                tick: _tick,
                price: price,
                liquidityNet: price == Pricing.MAX_TICK_PRICE ? ZERO : liquidityForTick(price)
            });
    }

    /// @inheritdoc IPoolCore
    function ticks() external view returns (IPoolInternal.TickWithLiquidity[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 liquidityRate = l.liquidityRate;
        UD60x18 prev = l.tickIndex.prev(l.currentTick);
        UD60x18 curr = l.currentTick;

        uint256 maxTicks = (ONE / Pricing.MIN_TICK_DISTANCE).unwrap() / 1e18;
        uint256 count;

        IPoolInternal.TickWithLiquidity[] memory _ticks = new IPoolInternal.TickWithLiquidity[](maxTicks);

        if (l.currentTick != Pricing.MIN_TICK_PRICE) {
            while (true) {
                liquidityRate = liquidityRate.add(l.ticks[curr].delta);

                if (prev == Pricing.MIN_TICK_PRICE) {
                    break;
                }

                curr = prev;
                prev = l.tickIndex.prev(prev);
            }

            _ticks[count++] = IPoolInternal.TickWithLiquidity({
                tick: l.ticks[prev],
                price: prev,
                liquidityNet: liquidityForRange(prev, curr, liquidityRate)
            });
        }

        prev = curr;

        while (true) {
            if (curr <= l.currentTick) {
                liquidityRate = liquidityRate.sub(l.ticks[curr].delta);
            } else {
                liquidityRate = liquidityRate.add(l.ticks[curr].delta);
            }

            curr = l.tickIndex.next(curr);

            _ticks[count++] = IPoolInternal.TickWithLiquidity({
                tick: l.ticks[prev],
                price: prev,
                liquidityNet: liquidityForRange(prev, curr, liquidityRate)
            });

            if (curr == Pricing.MAX_TICK_PRICE) {
                _ticks[count++] = IPoolInternal.TickWithLiquidity({
                    tick: l.ticks[curr],
                    price: curr,
                    liquidityNet: ZERO
                });
                break;
            }

            prev = curr;
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
    function liquidityForTick(UD60x18 price) public view returns (UD60x18 liquidityNet) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 liquidityRate = l.liquidityRate;

        if (price >= Pricing.MAX_TICK_PRICE) revert Pool__InvalidTickPrice();

        // If the tick is found, we can calculate the liquidity
        if (l.currentTick == price) {
            return liquidityForRange(l.currentTick, l.tickIndex.next(l.currentTick), liquidityRate);
        }

        UD60x18 prev = l.tickIndex.prev(l.currentTick);
        UD60x18 next = l.currentTick;

        // If the price is less than the current tick, we need to search left
        if (price < l.currentTick) {
            while (true) {
                if (prev == price) {
                    return liquidityForRange(prev, next, liquidityRate);
                }

                // If we reached the end of the left side, the tick does not exist
                if (prev == Pricing.MIN_TICK_PRICE) {
                    revert Pool__InvalidTickPrice();
                }

                // Otherwise, add the delta to the liquidity rate, and move to the next tick
                liquidityRate = liquidityRate.add(l.ticks[prev].delta);
                next = prev;
                prev = l.tickIndex.prev(prev);
            }
        }

        prev = l.currentTick;

        // The tick must be to the right side, search right for the tick
        while (true) {
            next = l.tickIndex.next(prev);

            if (next == price) {
                return liquidityForRange(prev, next, liquidityRate);
            }

            // If we reached the end of the right side, the tick does not exist
            if (next == Pricing.MAX_TICK_PRICE) {
                revert Pool__InvalidTickPrice();
            }

            liquidityRate = liquidityRate.add(l.ticks[next].delta);
            prev = next;
        }

        revert Pool__InvalidTickPrice();
    }

    /// @inheritdoc IPoolCore
    function liquidityForRange(
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 liquidityRate
    ) public pure returns (UD60x18 liquidityNet) {
        return
            Pricing.liquidity(
                Pricing.Args({
                    lower: lower,
                    upper: upper,
                    liquidityRate: liquidityRate,
                    marketPrice: ZERO, // Not used
                    isBuy: false // Not used
                })
            );
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
    function exercise() external nonReentrant returns (uint256) {
        return _exercise(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function exerciseFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(costPerHolder);
        uint256[] memory exerciseValues = new uint256[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _revertIfAgentNotAuthorized(holders[i], msg.sender);
                _revertIfCostNotAuthorized(holders[i], _cost);
            }

            exerciseValues[i] = _exercise(holders[i], _cost);
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, holders.length * costPerHolder);
        return exerciseValues;
    }

    /// @inheritdoc IPoolCore
    function settle() external nonReentrant returns (uint256) {
        return _settle(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function settleFor(
        address[] calldata holders,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(costPerHolder);
        uint256[] memory collateral = new uint256[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _revertIfAgentNotAuthorized(holders[i], msg.sender);
                _revertIfCostNotAuthorized(holders[i], _cost);
            }

            collateral[i] = _settle(holders[i], _cost);
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, holders.length * costPerHolder);
        return collateral;
    }

    /// @inheritdoc IPoolCore
    function settlePosition(Position.Key calldata p) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _revertIfOperatorNotAuthorized(p.operator);
        return _settlePosition(p.toKeyInternal(l.strike, l.isCallPool), ZERO);
    }

    /// @inheritdoc IPoolCore
    function settlePositionFor(
        Position.Key[] calldata p,
        uint256 costPerHolder
    ) external nonReentrant returns (uint256[] memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(costPerHolder);
        uint256[] memory collateral = new uint256[](p.length);

        for (uint256 i = 0; i < p.length; i++) {
            if (p[i].operator != msg.sender) {
                _revertIfAgentNotAuthorized(p[i].operator, msg.sender);
                _revertIfCostNotAuthorized(p[i].operator, _cost);
            }

            collateral[i] = _settlePosition(p[i].toKeyInternal(l.strike, l.isCallPool), _cost);
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, p.length * costPerHolder);
        return collateral;
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
}
