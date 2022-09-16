// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ITicks} from "./ITicks.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {LinkedList} from "../libraries/LinkedList.sol";

contract Ticks is ITicks {
    using PoolStorage for PoolStorage.Layout;
    using LinkedList for LinkedList.List;

    error Ticks__InvalidInsertLocation();
    error Ticks__InvalidInsert();
    error Ticks__FailedInsert();

    uint256 private constant MAX_UINT256 = uint256(int256(-1));

    /**
     * @notice Get the left and right Tick to insert a new Tick between.
     * @dev To be called from off-chain, then left and right points passed in
     *      to deposit/withdraw (correctness of left/right points can be
     *      verified much cheaper on-chain than finding on-chain)
     * @param lower The id of the lower-bound Tick for a new position.
     * @param upper The id of the upper-bound Tick for a new position.
     * @param current The Pool's current left tick id.
     * @return left The left Tick from the new position
     * @return right The right Tick from the new position
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
            left = l.tickIndex.getNextNode(right);
        }

        while (right > 0 && l.tickIndex.getPreviousNode(right) >= upper) {
            right = l.tickIndex.getPreviousNode(right);
        }

        if (
            left == 0 ||
            right == 0 ||
            left == MAX_UINT256 ||
            right == MAX_UINT256
        ) revert Ticks__InvalidInsertLocation();
    }

    /**
     * @notice Creates a Tick for a given price, or returns the existing tick.
     * @param price The price of the Tick
     * @return tick The Tick for a given price
     */
    function getOrCreateTick(uint256 price)
        internal
        returns (TickData memory tick)
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.tickIndex.nodeExists(price)) return l.ticks[price];

        tick = price <= l.marketPrice
            ? TickData(price, 0, l.exposure)
            : TickData(price, 0, PoolStorage.Exposure(0, 0, 0, 0, 0, 0));

        l.ticks[price] = tick;
    }
}
