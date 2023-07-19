// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

library DoublyLinkedListUD60x18 {
    using DoublyLinkedList for DoublyLinkedList.Bytes32List;

    /// @notice Returns true if the doubly linked list `self` contains the `value`
    function contains(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal view returns (bool) {
        return self.contains(bytes32(value.unwrap()));
    }

    /// @notice Returns the stored element before `value` in the doubly linked list `self`
    function prev(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal view returns (UD60x18) {
        return ud(uint256(self.prev(bytes32(value.unwrap()))));
    }

    /// @notice Returns the stored element after `value` in the doubly linked list `self`
    function next(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal view returns (UD60x18) {
        return ud(uint256(self.next(bytes32(value.unwrap()))));
    }

    /// @notice Returns true if `newValue` was successfully inserted before `nextValue` in the doubly linked list `self`
    function insertBefore(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 nextValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.insertBefore(bytes32(nextValue.unwrap()), bytes32(newValue.unwrap()));
    }

    /// @notice Returns true if `newValue` was successfully inserted after `prevValue` in the doubly linked list `self`
    function insertAfter(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 prevValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.insertAfter(bytes32(prevValue.unwrap()), bytes32(newValue.unwrap()));
    }

    /// @notice Returns true if `value` was successfully inserted at the end of the doubly linked list `self`
    function push(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal returns (bool status) {
        status = self.push(bytes32(value.unwrap()));
    }

    /// @notice Removes the first element in the doubly linked list `self`, returns the removed element `value`
    function pop(DoublyLinkedList.Bytes32List storage self) internal returns (UD60x18 value) {
        value = ud(uint256(self.pop()));
    }

    /// @notice Removes the last element in the doubly linked list `self`, returns the removed element `value`
    function shift(DoublyLinkedList.Bytes32List storage self) internal returns (UD60x18 value) {
        value = ud(uint256(self.shift()));
    }

    /// @notice Returns true if `value` was successfully inserted at the front of the doubly linked list `self`
    function unshift(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal returns (bool status) {
        status = self.unshift(bytes32(value.unwrap()));
    }

    /// @notice Returns true if `value` was successfully removed from the doubly linked list `self`
    function remove(DoublyLinkedList.Bytes32List storage self, UD60x18 value) internal returns (bool status) {
        status = self.remove(bytes32(value.unwrap()));
    }

    /// @notice Returns true if `oldValue` was successfully replaced with `newValue` in the doubly linked list `self`
    function replace(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 oldValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.replace(bytes32(oldValue.unwrap()), bytes32(newValue.unwrap()));
    }
}
