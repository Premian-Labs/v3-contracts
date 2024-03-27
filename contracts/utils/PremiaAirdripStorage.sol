// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

library PremiaAirdripStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.PremiaAirdrip");

    struct Layout {
        // whether the contract has been initialized
        bool initialized;
        // premia per influence per vesting interval
        UD60x18 emissionRate;
        // dates which the premia airdrip will vest
        uint256[12] vestingDates;
        // total influence per user
        mapping(address user => UD60x18 influence) influence;
        // amount claimed at each vest date
        mapping(address usermapping => mapping(uint256 vestDate => uint256 amountClaimed)) allocations;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
