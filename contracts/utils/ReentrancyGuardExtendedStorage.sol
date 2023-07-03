// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

library ReentrancyGuardExtendedStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.ReentrancyGuardExtended");

    struct Layout {
        bool disabled;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
