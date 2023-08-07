// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library RelayerAccessManagerStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.RelayerAccessManager");

    struct Layout {
        EnumerableSet.AddressSet whitelistedRelayers;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
