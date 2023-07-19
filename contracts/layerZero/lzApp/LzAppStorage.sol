// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library LzAppStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.LzApp");

    struct Layout {
        mapping(uint16 => bytes) trustedRemote;
        address precrime;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
