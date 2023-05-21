// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library EnumerableSetUD60x18 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Returns the element at a given index `i` in the enumerable set `self`
    function at(EnumerableSet.Bytes32Set storage self, uint256 i) internal view returns (UD60x18) {
        return UD60x18.wrap(uint256(self.at(i)));
    }

    /// @notice Returns true if the enumerable set `self` contains `value`
    function contains(EnumerableSet.Bytes32Set storage self, UD60x18 value) internal view returns (bool) {
        return self.contains(bytes32(value.unwrap()));
    }

    /// @notice Returns the index of `value` in the enumerable set `self`
    function indexOf(EnumerableSet.Bytes32Set storage self, UD60x18 value) internal view returns (uint256) {
        return self.indexOf(bytes32(value.unwrap()));
    }

    /// @notice Returns the number of elements in the enumerable set `self`
    function length(EnumerableSet.Bytes32Set storage self) internal view returns (uint256) {
        return self.length();
    }

    /// @notice Returns true if `value` is added to the enumerable set `self`
    function add(EnumerableSet.Bytes32Set storage self, UD60x18 value) internal returns (bool) {
        return self.add(bytes32(value.unwrap()));
    }

    /// @notice Returns true if `value` is removed from the enumerable set `self`
    function remove(EnumerableSet.Bytes32Set storage self, UD60x18 value) internal returns (bool) {
        return self.remove(bytes32(value.unwrap()));
    }

    /// @notice Returns an array of all elements in the enumerable set `self`
    function toArray(EnumerableSet.Bytes32Set storage self) internal view returns (UD60x18[] memory) {
        bytes32[] memory src = self.toArray();
        UD60x18[] memory tgt = new UD60x18[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            tgt[i] = UD60x18.wrap(uint256(src[i]));
        }
        return tgt;
    }
}
