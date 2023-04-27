// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

library UserSettingsStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.UserSettings");

    struct Layout {
        mapping(address => address[]) authorizedAgents;
        mapping(address => uint256) authorizedCost;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
