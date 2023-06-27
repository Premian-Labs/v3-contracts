// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library ReentrancyGuardExtendedStorage {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.ReentrancyGuardExtended");

    struct Layout {
        bool disabled;
        EnumerableSet.Bytes32Set selectorsIgnored;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
