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

    /*
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

        right = current;
        while (right > 0 && right < upper) {
            left = l.tickIndex.getNextNode(right);
        }

        if (left == 0 || right == 0) revert Ticks__InvalidInsertLocation();
    }
}
