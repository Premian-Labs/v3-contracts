// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

library DoublyLinkedListUD60x18 {
    using DoublyLinkedList for DoublyLinkedList.Bytes32List;

    function contains(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal view returns (bool) {
        return self.contains(bytes32(value.unwrap()));
    }

    function prev(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal view returns (UD60x18) {
        return UD60x18.wrap(uint256(self.prev(bytes32(value.unwrap()))));
    }

    function next(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal view returns (UD60x18) {
        return UD60x18.wrap(uint256(self.next(bytes32(value.unwrap()))));
    }

    function insertBefore(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 nextValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.insertBefore(
            bytes32(nextValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }

    function insertAfter(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 prevValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.insertAfter(
            bytes32(prevValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }

    function push(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = self.push(bytes32(value.unwrap()));
    }

    function pop(
        DoublyLinkedList.Bytes32List storage self
    ) internal returns (UD60x18 value) {
        value = UD60x18.wrap(uint256(self.pop()));
    }

    function shift(
        DoublyLinkedList.Bytes32List storage self
    ) internal returns (UD60x18 value) {
        value = UD60x18.wrap(uint256(self.shift()));
    }

    function unshift(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = self.unshift(bytes32(value.unwrap()));
    }

    function remove(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = self.remove(bytes32(value.unwrap()));
    }

    function replace(
        DoublyLinkedList.Bytes32List storage self,
        UD60x18 oldValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = self.replace(
            bytes32(oldValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }
}
