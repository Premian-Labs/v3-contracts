// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

/// @notice Derived from https://github.com/solidstate-network/solidstate-solidity/blob/master/contracts/data/DoublyLinkedList.sol
library DoublyLinkedListUD60x18 {
    struct DoublyLinkedListInternal {
        mapping(bytes32 => bytes32) _nextValues;
        mapping(bytes32 => bytes32) _prevValues;
    }

    struct UD60x18List {
        DoublyLinkedListInternal _inner;
    }

    error DoublyLinkedList__InvalidInput();
    error DoublyLinkedList__NonExistentEntry();

    function contains(
        UD60x18List storage self,
        UD60x18 value
    ) internal view returns (bool) {
        return _contains(self._inner, bytes32(value.unwrap()));
    }

    function prev(
        UD60x18List storage self,
        UD60x18 value
    ) internal view returns (UD60x18) {
        return
            UD60x18.wrap(uint256(_prev(self._inner, bytes32(value.unwrap()))));
    }

    function next(
        UD60x18List storage self,
        UD60x18 value
    ) internal view returns (UD60x18) {
        return
            UD60x18.wrap(uint256(_next(self._inner, bytes32(value.unwrap()))));
    }

    function insertBefore(
        UD60x18List storage self,
        UD60x18 nextValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = _insertBefore(
            self._inner,
            bytes32(nextValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }

    function insertAfter(
        UD60x18List storage self,
        UD60x18 prevValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = _insertAfter(
            self._inner,
            bytes32(prevValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }

    function push(
        UD60x18List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = _push(self._inner, bytes32(value.unwrap()));
    }

    function pop(UD60x18List storage self) internal returns (UD60x18 value) {
        value = UD60x18.wrap(uint256(_pop(self._inner)));
    }

    function shift(UD60x18List storage self) internal returns (UD60x18 value) {
        value = UD60x18.wrap(uint256(_shift(self._inner)));
    }

    function unshift(
        UD60x18List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = _unshift(self._inner, bytes32(value.unwrap()));
    }

    function remove(
        UD60x18List storage self,
        UD60x18 value
    ) internal returns (bool status) {
        status = _remove(self._inner, bytes32(value.unwrap()));
    }

    function replace(
        UD60x18List storage self,
        UD60x18 oldValue,
        UD60x18 newValue
    ) internal returns (bool status) {
        status = _replace(
            self._inner,
            bytes32(oldValue.unwrap()),
            bytes32(newValue.unwrap())
        );
    }

    function _contains(
        DoublyLinkedListInternal storage self,
        bytes32 value
    ) private view returns (bool) {
        return
            value != 0 &&
            (self._nextValues[value] != 0 || self._prevValues[0] == value);
    }

    function _prev(
        DoublyLinkedListInternal storage self,
        bytes32 nextValue
    ) private view returns (bytes32 prevValue) {
        prevValue = self._prevValues[nextValue];
        if (
            nextValue != 0 &&
            prevValue == 0 &&
            _next(self, prevValue) != nextValue
        ) revert DoublyLinkedList__NonExistentEntry();
    }

    function _next(
        DoublyLinkedListInternal storage self,
        bytes32 prevValue
    ) private view returns (bytes32 nextValue) {
        nextValue = self._nextValues[prevValue];
        if (
            prevValue != 0 &&
            nextValue == 0 &&
            _prev(self, nextValue) != prevValue
        ) revert DoublyLinkedList__NonExistentEntry();
    }

    function _insertBefore(
        DoublyLinkedListInternal storage self,
        bytes32 nextValue,
        bytes32 newValue
    ) private returns (bool status) {
        status = _insertBetween(
            self,
            _prev(self, nextValue),
            nextValue,
            newValue
        );
    }

    function _insertAfter(
        DoublyLinkedListInternal storage self,
        bytes32 prevValue,
        bytes32 newValue
    ) private returns (bool status) {
        status = _insertBetween(
            self,
            prevValue,
            _next(self, prevValue),
            newValue
        );
    }

    function _insertBetween(
        DoublyLinkedListInternal storage self,
        bytes32 prevValue,
        bytes32 nextValue,
        bytes32 newValue
    ) private returns (bool status) {
        if (newValue == 0) revert DoublyLinkedList__InvalidInput();

        if (!_contains(self, newValue)) {
            _link(self, prevValue, newValue);
            _link(self, newValue, nextValue);
            status = true;
        }
    }

    function _push(
        DoublyLinkedListInternal storage self,
        bytes32 value
    ) private returns (bool status) {
        status = _insertBetween(self, _prev(self, 0), 0, value);
    }

    function _pop(
        DoublyLinkedListInternal storage self
    ) private returns (bytes32 value) {
        value = _prev(self, 0);
        _remove(self, value);
    }

    function _shift(
        DoublyLinkedListInternal storage self
    ) private returns (bytes32 value) {
        value = _next(self, 0);
        _remove(self, value);
    }

    function _unshift(
        DoublyLinkedListInternal storage self,
        bytes32 value
    ) private returns (bool status) {
        status = _insertBetween(self, 0, _next(self, 0), value);
    }

    function _remove(
        DoublyLinkedListInternal storage self,
        bytes32 value
    ) private returns (bool status) {
        if (_contains(self, value)) {
            _link(self, _prev(self, value), _next(self, value));
            delete self._prevValues[value];
            delete self._nextValues[value];
            status = true;
        }
    }

    function _replace(
        DoublyLinkedListInternal storage self,
        bytes32 oldValue,
        bytes32 newValue
    ) private returns (bool status) {
        if (!_contains(self, oldValue))
            revert DoublyLinkedList__NonExistentEntry();

        status = _insertBetween(
            self,
            _prev(self, oldValue),
            _next(self, oldValue),
            newValue
        );

        if (status) {
            delete self._prevValues[oldValue];
            delete self._nextValues[oldValue];
        }
    }

    function _link(
        DoublyLinkedListInternal storage self,
        bytes32 prevValue,
        bytes32 nextValue
    ) private {
        self._nextValues[prevValue] = nextValue;
        self._prevValues[nextValue] = prevValue;
    }
}
