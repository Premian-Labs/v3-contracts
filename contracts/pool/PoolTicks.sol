// SPDX-License-Identifier: BUSL-1.1
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

import {PoolInternal} from "./PoolInternal.sol";

contract PoolTicks is IPoolTicks, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
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
}
