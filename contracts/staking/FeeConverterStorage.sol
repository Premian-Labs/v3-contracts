// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

library FeeConverterStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.FeeConverter");

    struct Layout {
        // Whether the address is authorized to call the convert function or not
        mapping(address => bool) isAuthorized;
        // The treasury address which will receive a portion of the protocol fees
        address treasury;
        // The percentage of protocol fees the treasury will get
        UD60x18 treasuryShare;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
