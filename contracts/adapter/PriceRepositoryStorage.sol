// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library PriceRepositoryStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.PriceRepository");

    struct Layout {
        mapping(address base => mapping(address quote => mapping(uint256 timestamp => UD60x18 price))) prices;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
