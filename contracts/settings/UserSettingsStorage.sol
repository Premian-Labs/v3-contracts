// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IUserSettings} from "./IUserSettings.sol";

library UserSettingsStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.UserSettings");

    struct Layout {
        mapping(address user => mapping(address operator => EnumerableSet.UintSet)) authorizations;
        mapping(address user => uint256 cost) authorizedCost;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
