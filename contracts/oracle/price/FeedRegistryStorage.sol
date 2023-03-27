// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

library FeedRegistryStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.FeedRegistry");

    struct Layout {
        mapping(bytes32 => address) feeds;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
