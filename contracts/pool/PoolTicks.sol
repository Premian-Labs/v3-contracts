// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

import {PoolStorage} from "./PoolStorage.sol";

import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

import {PoolInternal} from "./PoolInternal.sol";

contract PoolTicks is IPoolTicks, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using Tick for Tick.Data;
    using Math for int256;
    using SafeCast for uint256;
    using UintUtils for uint256;

    error PoolTicks__InvalidInsertLocation();
    error PoolTicks__InvalidInsert();
    error PoolTicks__FailedInsert();

    /// @notice Get the left and right Tick to insert a new Tick between.
    /// @dev To be called from off-chain, then left and right points passed in
    ///      to deposit/withdraw (correctness of left/right points can be
    ///      verified much cheaper on-chain than finding on-chain)
    /// @param lower The normalized price of the lower-bound Tick for a new position.
    /// @param upper The normalized price the upper-bound Tick for a new position.
    /// @param current The Pool's current left tick normalized price.
    /// @return left The normalized price of the left Tick from the new position
    /// @return right The normalized price of the right Tick from the new position
    function getInsertTicks(
        uint256 lower,
        uint256 upper,
        uint256 current
    ) external view returns (uint256 left, uint256 right) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        left = current;
        while (left != 0 && left > lower) {
            left = l.tickIndex.prev(left);
        }

        while (left != 0 && l.tickIndex.next(left) <= lower) {
            left = l.tickIndex.next(left);
        }

        right = current;
        while (right != 0 && right < upper) {
            right = l.tickIndex.next(right);
        }

        while (right != 0 && l.tickIndex.prev(right) >= upper) {
            right = l.tickIndex.prev(right);
        }

        if (left == 0 || right == 0) revert PoolTicks__InvalidInsertLocation();
    }
}
