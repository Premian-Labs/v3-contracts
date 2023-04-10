// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

library VaultSettingsStorage {
    using VaultSettingsStorage for VaultSettingsStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VaultSettings");

    struct Layout {
        mapping(bytes32 => bytes) settings;
        mapping(bytes32 => address) implementations;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
