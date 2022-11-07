// SPDX-License-Identifier: UNLICENSED

// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

import {PoolStorage} from "./PoolStorage.sol";

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

contract PoolTicks is IPoolTicks {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Data;
    using LinkedList for LinkedList.List;
    using Tick for Tick.Data;
    using Math for int256;
    using SafeCast for uint256;
    using UintUtils for uint256;

    error PoolTicks__InvalidInsertLocation();
    error PoolTicks__InvalidInsert();
    error PoolTicks__FailedInsert();

    uint256 private constant MAX_UINT256 = type(uint256).max;

    /**
     * @notice Get the left and right Tick to insert a new Tick between.
     * @dev To be called from off-chain, then left and right points passed in
     *      to deposit/withdraw (correctness of left/right points can be
     *      verified much cheaper on-chain than finding on-chain)
     * @param lower The normalized price of the lower-bound Tick for a new position.
     * @param upper The normalized price the upper-bound Tick for a new position.
     * @param current The Pool's current left tick normalized price.
     * @return left The normalized price of the left Tick from the new position
     * @return right The normalized price of the right Tick from the new position
     */
    function getInsertTicks(
        uint256 lower,
        uint256 upper,
        uint256 current
    ) external view returns (uint256 left, uint256 right) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        left = current;
        while (left > 0 && left > lower) {
            left = l.tickIndex.getPreviousNode(left);
        }

        while (left < MAX_UINT256 && l.tickIndex.getNextNode(left) <= lower) {
            left = l.tickIndex.getNextNode(left);
        }

        right = current;
        while (right < MAX_UINT256 && right < upper) {
            right = l.tickIndex.getNextNode(right);
        }

        while (right > 0 && l.tickIndex.getPreviousNode(right) >= upper) {
            right = l.tickIndex.getPreviousNode(right);
        }

        if (
            left == 0 ||
            right == 0 ||
            left == MAX_UINT256 ||
            right == MAX_UINT256
        ) revert PoolTicks__InvalidInsertLocation();
    }

    /**
     * @notice Adds liquidity to a pair of Ticks and if necessary, inserts
     *         the Tick(s) into the doubly-linked Tick list.
     *
     * @param lower The normalized price of the lower-bound Tick for a new position.
     * @param upper The normalized price of the upper-bound Tick for a new position.
     * @param left The normalized price of the left Tick for a new position.
     * @param right The normalized price of the right Tick for a new position.
     * @param position The Position to insert into Ticks.
     */
    function _insert(
        uint256 lower,
        uint256 upper,
        uint256 left,
        uint256 right,
        Position.Data memory position
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (
            left > lower ||
            l.tickIndex.getNextNode(left) < lower ||
            right < upper ||
            l.tickIndex.getPreviousNode(right) > upper ||
            left == right ||
            lower == upper
        ) revert PoolTicks__InvalidInsert();

        int256 delta = position.phi(l.minTickDistance()).toInt256();

        if (position.rangeSide == PoolStorage.Side.SELL) {
            l.ticks[lower].delta += delta;
            l.ticks[upper].delta -= delta;
        } else {
            l.ticks[lower].delta -= delta;
            l.ticks[upper].delta += delta;
        }

        if (left != lower) {
            if (l.tickIndex.insertAfter(left, lower) == false)
                revert PoolTicks__FailedInsert();

            if (position.rangeSide == PoolStorage.Side.SELL) {
                if (position.lower == l.marketPrice) {
                    l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
                    l.liquidityRate = l.liquidityRate.add(delta);

                    if (l.tick < position.lower) l.tick = lower;
                }
            } else {
                l.ticks[lower] = l.ticks[lower].cross(l.globalFeeRate);
            }
        }

        if (right != upper) {
            if (l.tickIndex.insertBefore(right, upper) == false)
                revert PoolTicks__FailedInsert();

            if (position.rangeSide == PoolStorage.Side.BUY) {
                l.ticks[upper] = l.ticks[upper].cross(l.globalFeeRate);
                if (l.tick <= position.upper) {
                    l.liquidityRate = l.liquidityRate.add(delta);
                }
                if (l.tick < position.lower) {
                    l.tick = lower;
                }
            }
        }
    }

    /**
     * @notice Removes liquidity from a pair of Ticks and if necessary, removes
     *         the Tick(s) from the doubly-linked Tick list.
     * @param lower The normalized price of the lower-bound Tick for a new position.
     * @param upper The normalized price of the upper-bound Tick for a new position.
     * @param position The Position to insert into Ticks.
     */
    function _remove(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice,
        Position.Data memory position
    ) internal {
        PoolStorage.Layout storage l = PoolStorage.layout();

        int256 phi = position.phi(l.minTickDistance()).toInt256();
        bool leftRangeSide = position.rangeSide == PoolStorage.Side.BUY;
        bool rightRangeSide = position.rangeSide == PoolStorage.Side.SELL;

        int256 lowerDelta = l.ticks[lower].delta;
        int256 upperDelta = l.ticks[upper].delta;

        // right-side original state:
        //   lower_tick.delta += phi
        //   upper_tick.delta -= phi

        if (rightRangeSide) {
            if (lower > marketPrice) {
                // |---------p----l------------> original state
                lowerDelta -= phi;
            } else {
                // |------------l---p---------> left-tick crossed
                lowerDelta += phi;
            }

            if (upper > marketPrice) {
                // |------------p----u--------> original state
                upperDelta += phi;
            } else {
                // |----------------u----p----> right-tick crossed
                upperDelta -= phi;
            }
        }

        // left-side original state:
        //   lower_tick.delta -= phi
        //   upper_tick.delta += phi

        if (leftRangeSide) {
            if (upper < marketPrice) {
                // <---------u----p-----------| original state
                upperDelta -= phi;
            } else {
                // # <--------------p----u------| right-tick crossed
                upperDelta += phi;
            }

            if (lower < marketPrice) {
                // <-----l----p---------------| original state
                lowerDelta += phi;
            } else {
                // <---------p---l------------| left-tick crossed
                lowerDelta -= phi;
            }
        }

        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        if (lowerDelta.abs() == 0) {
            l.tickIndex.remove(lower);
            delete l.ticks[lower];
        }

        // ToDo : Test precision rounding errors and if we need to increase from 0 (Most likely yes)
        if (upperDelta.abs() == 0) {
            l.tickIndex.remove(upper);
            delete l.ticks[upper];
        }
    }

    /**
     * @notice Creates a Tick for a given price, or returns the existing tick.
     * @param price The price of the Tick
     * @return tick The Tick for a given price
     */
    function _getOrCreateTick(uint256 price)
        internal
        returns (Tick.Data memory tick)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.nodeExists(price)) return l.ticks[price];

        tick = Tick.Data(
            price,
            0,
            price <= l.marketPrice ? l.globalFeeRate : 0
        );

        l.ticks[price] = tick;
    }
}
