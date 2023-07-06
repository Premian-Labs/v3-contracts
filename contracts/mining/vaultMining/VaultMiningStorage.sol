// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IVaultMining} from "./IVaultMining.sol";

library VaultMiningStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.VaultMining");

    struct Layout {
        // Amount of rewards distributed per year
        UD60x18 rewardsPerYear;
        // Total rewards left to distribute
        UD60x18 rewardsAvailable;
        mapping(address pool => IVaultMining.VaultInfo infos) vaultInfo;
        mapping(address pool => mapping(address user => IVaultMining.UserInfo info)) userInfo;
        // Total votes across all pools
        UD60x18 totalVotes;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
