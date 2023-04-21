// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

library UserSettingsStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.UserSettings");

    struct Layout {
        mapping(address => address[]) authorizedAgents;
        mapping(address => uint256) authorizedTxCostAndFee;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
