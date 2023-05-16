// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library EnumerableSetUD60x18 {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    function at(
        EnumerableSet.Bytes32Set storage self,
        uint256 i
    ) internal view returns (UD60x18) {
        return UD60x18.wrap(uint256(self.at(i)));
    }

    function contains(
        EnumerableSet.Bytes32Set storage self,
        UD60x18 value
    ) internal view returns (bool) {
        return self.contains(bytes32(value.unwrap()));
    }

    function indexOf(
        EnumerableSet.Bytes32Set storage self,
        UD60x18 value
    ) internal view returns (uint256) {
        return self.indexOf(bytes32(value.unwrap()));
    }

    function length(
        EnumerableSet.Bytes32Set storage self
    ) internal view returns (uint256) {
        return self.length();
    }

    function add(
        EnumerableSet.Bytes32Set storage self,
        UD60x18 value
    ) internal returns (bool) {
        return self.add(bytes32(value.unwrap()));
    }

    function remove(
        EnumerableSet.Bytes32Set storage self,
        UD60x18 value
    ) internal returns (bool) {
        return self.remove(bytes32(value.unwrap()));
    }

    function toArray(
        EnumerableSet.Bytes32Set storage self
    ) internal view returns (UD60x18[] memory) {
        bytes32[] memory src = self.toArray();
        UD60x18[] memory tgt = new UD60x18[](src.length);
        for (uint256 i = 0; i < src.length; i++) {
            tgt[i] = UD60x18.wrap(uint256(src[i]));
        }
        return tgt;
    }
}
