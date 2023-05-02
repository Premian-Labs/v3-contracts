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

import {Pricing} from "../libraries/Pricing.sol";
import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";

import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal, ReentrancyGuard {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using SafeERC20 for IERC20;
    using PRBMathExtra for UD60x18;

    constructor(
        address factory,
        address router,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver,
        address vxPremia
    )
        PoolInternal(
            factory,
            router,
            exchangeHelper,
            wrappedNativeToken,
            feeReceiver,
            vxPremia
        )
    {}

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
                _takerFee(
                    l,
                    taker,
                    size,
                    l.fromPoolTokenDecimals(premium),
                    isPremiumNormalized
                )
            );
    }

    /// @inheritdoc IPoolCore
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint64 maturity,
            bool isCallPool
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (
            l.base,
            l.quote,
            l.oracleAdapter,
            l.strike,
            l.maturity,
            l.isCallPool
        );
    }

    /// @inheritdoc IPoolCore
    function tick(
        UD60x18 index
    ) external view returns (IPoolInternal.TickWithLiquidity memory) {
        IPoolInternal.Tick memory _tick = PoolStorage.layout().ticks[index];

        return
            IPoolInternal.TickWithLiquidity({
                tick: _tick,
                index: index.unwrap(),
                liquidityNet: index == Pricing.MAX_TICK_PRICE
                    ? UD60x18.wrap(0)
                    : getLiquidityForTick(index)
            });
    }

    /// @inheritdoc IPoolCore
    function getLiquidityForTick(UD60x18 index) public view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 liquidityRate = l.liquidityRate;
        UD60x18 currentTick = l.currentTick;

        if (index >= Pricing.MAX_TICK_PRICE) revert Pool__InvalidTickIndex();

        // If the tick is found, we can calculate the liquidity
        if (l.currentTick == index) {
            return
                getLiquidityForRange(
                    currentTick,
                    l.tickIndex.next(currentTick),
                    liquidityRate
                );
        }

        UD60x18 next = currentTick;

        // If the current tick has a previous tick, we need to search left first for the tick
        if (l.currentTick != Pricing.MIN_TICK_PRICE) {
            UD60x18 prev = l.tickIndex.prev(currentTick);

            while (true) {
                if (prev == index) {
                    return getLiquidityForRange(prev, next, liquidityRate);
                }

                // If we reached the end of the left side, the tick must be on the right side
                if (prev == Pricing.MIN_TICK_PRICE) {
                    // Reset the liquidity rate to the current, so we can traverse from currentTick
                    liquidityRate = l.liquidityRate;
                    break;
                }

                // Otherwise, add the delta to the liquidity rate, and move to the next tick
                liquidityRate = liquidityRate.add(l.ticks[prev].delta);
                next = prev;
                prev = l.tickIndex.prev(prev);
            }
        }

        next = l.tickIndex.next(currentTick);

        // The tick must be to the right side, search right for the tick
        while (true) {
            UD60x18 nextIndex = l.tickIndex.next(next);
            liquidityRate = liquidityRate.add(l.ticks[next].delta);

            if (next == index) {
                return getLiquidityForRange(next, nextIndex, liquidityRate);
            }

            // If we reached the end of the right side, the tick does not exist
            if (next == Pricing.MAX_TICK_PRICE) {
                revert Pool__InvalidTickIndex();
            }

            next = nextIndex;
        }

        revert Pool__InvalidTickIndex();
    }

    /// @inheritdoc IPoolCore
    function getLiquidityForTicks()
        external
        view
        returns (IPoolInternal.TickWithLiquidity[] memory)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 maxTicks = (UD60x18.wrap(1e18) / Pricing.MIN_TICK_DISTANCE)
            .unwrap();
        IPoolInternal.TickWithLiquidity[]
            memory ticks = new IPoolInternal.TickWithLiquidity[](maxTicks);

        UD60x18 liquidityRate = l.liquidityRate;
        UD60x18 currentTick = l.currentTick;
        UD60x18 next = currentTick;
        uint256 count = 1;

        ticks[currentTick.unwrap()] = IPoolInternal.TickWithLiquidity({
            tick: l.ticks[currentTick],
            index: currentTick.unwrap(),
            liquidityNet: getLiquidityForRange(
                currentTick,
                l.tickIndex.next(currentTick),
                liquidityRate
            )
        });

        if (l.currentTick != Pricing.MIN_TICK_PRICE) {
            UD60x18 prev = l.tickIndex.prev(currentTick);

            while (true) {
                ticks[prev.unwrap()] = IPoolInternal.TickWithLiquidity({
                    tick: l.ticks[prev],
                    index: prev.unwrap(),
                    liquidityNet: getLiquidityForRange(
                        prev,
                        next,
                        liquidityRate
                    )
                });
                count++;

                if (prev == Pricing.MIN_TICK_PRICE) {
                    liquidityRate = l.liquidityRate;
                    break;
                }

                liquidityRate = liquidityRate.add(l.ticks[prev].delta);
                next = prev;
                prev = l.tickIndex.prev(prev);
            }
        }

        next = l.tickIndex.next(currentTick);

        while (true) {
            UD60x18 nextIndex = l.tickIndex.next(next);
            liquidityRate = liquidityRate.add(l.ticks[next].delta);

            ticks[next.unwrap()] = IPoolInternal.TickWithLiquidity({
                tick: l.ticks[next],
                index: next.unwrap(),
                liquidityNet: getLiquidityForRange(
                    next,
                    nextIndex,
                    liquidityRate
                )
            });
            count++;

            if (nextIndex == Pricing.MAX_TICK_PRICE) {
                ticks[nextIndex.unwrap()] = IPoolInternal.TickWithLiquidity({
                    tick: l.ticks[nextIndex],
                    index: nextIndex.unwrap(),
                    liquidityNet: UD60x18.wrap(0)
                });
                count++;

                break;
            }

            next = nextIndex;
        }

        // Remove empty elements from array
        if (count < maxTicks) {
            assembly {
                mstore(ticks, sub(mload(ticks), sub(maxTicks, count)))
            }
        }

        return ticks;
    }

    /// @inheritdoc IPoolCore
    function getLiquidityForRange(
        UD60x18 index,
        UD60x18 nextIndex,
        UD60x18 liquidityRate
    ) public pure returns (UD60x18) {
        return
            ((nextIndex - index) * liquidityRate) / Pricing.MIN_TICK_DISTANCE;
    }

    /// @inheritdoc IPoolCore
    function claim(
        Position.Key calldata p
    ) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _claim(p.toKeyInternal(l.strike, l.isCallPool));
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(
        Position.Key calldata p
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];

        (UD60x18 pendingClaimableFees, ) = _pendingClaimableFees(
            l,
            p.toKeyInternal(l.strike, l.isCallPool),
            pData
        );

        return
            l.toPoolTokenDecimals(pData.claimableFees + pendingClaimableFees);
    }

    /// @inheritdoc IPoolCore
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size,
        Permit2.Data calldata permit
    ) external nonReentrant {
        return _writeFrom(underwriter, longReceiver, size, permit);
    }

    /// @inheritdoc IPoolCore
    function annihilate(UD60x18 size) external nonReentrant {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise(address holder) external nonReentrant returns (uint256) {
        return _exercise(holder);
    }

    /// @inheritdoc IPoolCore
    function settle(address holder) external nonReentrant returns (uint256) {
        return _settle(holder);
    }

    /// @inheritdoc IPoolCore
    function settlePosition(
        Position.Key calldata p
    ) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _settlePosition(p.toKeyInternal(l.strike, l.isCallPool));
    }

    /// @inheritdoc IPoolCore
    function getNearestTicksBelow(
        UD60x18 lower,
        UD60x18 upper
    )
        external
        view
        returns (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper)
    {
        return _getNearestTicksBelow(lower, upper);
    }

    /// @inheritdoc IPoolCore
    function transferPosition(
        Position.Key calldata srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(srcP.operator);
        _transferPosition(
            srcP.toKeyInternal(l.strike, l.isCallPool),
            newOwner,
            newOperator,
            size
        );
    }
}
