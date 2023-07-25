// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

library FeeConverterStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.FeeConverter");

    struct Layout {
        // Whether the address is authorized to call the convert function or not
        mapping(address => bool) isAuthorized;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
