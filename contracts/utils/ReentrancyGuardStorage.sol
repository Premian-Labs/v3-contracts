// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library ReentrancyGuardStorage {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    error ReentrancyGuard__ReentrantCall();

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.ReentrancyGuard");

    struct Layout {
        bool disabled;
        uint256 reentrancyStatus;
        EnumerableSet.Bytes32Set selectorsIgnored;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
