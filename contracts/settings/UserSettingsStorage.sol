// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library UserSettingsStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.UserSettings");

    struct Layout {
        // A set of actions `operator` has been authorized to perform on behalf of `user`
        mapping(address user => mapping(address operator => EnumerableSet.UintSet actions)) authorizedActions;
        mapping(address user => UD60x18 cost) authorizedCost;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
