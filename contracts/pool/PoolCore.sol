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
        address vxPremia
    )
        PoolInternal(factory, router, wrappedNativeToken, feeReceiver, vxPremia)
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
        UD60x18 price
    ) external view returns (IPoolInternal.TickWithLiquidity memory) {
        IPoolInternal.Tick memory _tick = PoolStorage.layout().ticks[price];

        return
            IPoolInternal.TickWithLiquidity({
                tick: _tick,
                price: price,
                liquidityNet: price == Pricing.MAX_TICK_PRICE
                    ? ZERO
                    : liquidityForTick(price)
            });
    }

    /// @inheritdoc IPoolCore
    function ticks()
        external
        view
        returns (IPoolInternal.TickWithLiquidity[] memory)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        uint256 maxTicks = (ONE / Pricing.MIN_TICK_DISTANCE).unwrap();

        IPoolInternal.TickWithLiquidity[]
            memory _ticks = new IPoolInternal.TickWithLiquidity[](maxTicks);

        UD60x18 liquidityRate = l.liquidityRate;
        UD60x18 currentTick = l.currentTick;
        UD60x18 next = currentTick;
        uint256 count = 1;

        _ticks[currentTick.unwrap()] = IPoolInternal.TickWithLiquidity({
            tick: l.ticks[currentTick],
            price: currentTick,
            liquidityNet: liquidityForRange(
                currentTick,
                l.tickIndex.next(currentTick),
                liquidityRate
            )
        });

        if (l.currentTick != Pricing.MIN_TICK_PRICE) {
            UD60x18 prev = l.tickIndex.prev(currentTick);

            while (true) {
                _ticks[prev.unwrap()] = IPoolInternal.TickWithLiquidity({
                    tick: l.ticks[prev],
                    price: prev,
                    liquidityNet: liquidityForRange(prev, next, liquidityRate)
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
            UD60x18 nextPrice = l.tickIndex.next(next);
            liquidityRate = liquidityRate.add(l.ticks[next].delta);

            _ticks[next.unwrap()] = IPoolInternal.TickWithLiquidity({
                tick: l.ticks[next],
                price: next,
                liquidityNet: liquidityForRange(next, nextPrice, liquidityRate)
            });
            count++;

            if (nextPrice == Pricing.MAX_TICK_PRICE) {
                _ticks[nextPrice.unwrap()] = IPoolInternal.TickWithLiquidity({
                    tick: l.ticks[nextPrice],
                    price: nextPrice,
                    liquidityNet: ZERO
                });
                count++;

                break;
            }

            next = nextPrice;
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
    function liquidityForTick(
        UD60x18 price
    ) public view returns (UD60x18 liquidityNet) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 liquidityRate = l.liquidityRate;
        UD60x18 currentTick = l.currentTick;

        if (price >= Pricing.MAX_TICK_PRICE) revert Pool__InvalidTickPrice();

        // If the tick is found, we can calculate the liquidity
        if (l.currentTick == price) {
            return
                liquidityForRange(
                    currentTick,
                    l.tickIndex.next(currentTick),
                    liquidityRate
                );
        }

        UD60x18 next = currentTick;

        // If the price is less than the current tick, we need to search left
        if (price < l.currentTick) {
            UD60x18 prev = l.tickIndex.prev(currentTick);

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

        next = l.tickIndex.next(currentTick);

        // The tick must be to the right side, search right for the tick
        while (true) {
            UD60x18 nextPrice = l.tickIndex.next(next);
            liquidityRate = liquidityRate.add(l.ticks[next].delta);

            if (next == price) {
                return liquidityForRange(next, nextPrice, liquidityRate);
            }

            // If we reached the end of the right side, the tick does not exist
            if (next == Pricing.MAX_TICK_PRICE) {
                revert Pool__InvalidTickPrice();
            }

            next = nextPrice;
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
        UD60x18 size
    ) external nonReentrant {
        return _writeFrom(underwriter, longReceiver, size);
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
