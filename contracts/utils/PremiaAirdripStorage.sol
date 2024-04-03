// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

library PremiaAirdripStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.PremiaAirdrip");

    struct Layout {
        // whether the contract has been initialized
        bool initialized;
        // premia per influence distributed per year
        UD60x18 premiaPerInfluence;
        // total influence of all users
        UD60x18 totalInfluence;
        // total influence per user
        mapping(address user => UD60x18 influence) influence;
        // total amount claimed per user
        mapping(address user => uint256 claimed) claimed;
        // timestamp of last claim per user
        mapping(address user => uint256 lastClaim) lastClaim;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
