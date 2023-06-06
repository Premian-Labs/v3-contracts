// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

library MiningPoolStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.mining.MiningPool");

    struct Layout {
        address base;
        address quote;
        address priceRepository;
        address paymentSplitter;
        // percentage of the asset spot price used to set the strike price
        UD60x18 percentOfSpot;
        // amount of time the option lasts
        uint256 daysToExpiry;
        // amount of time the exercise period lasts
        uint256 exerciseDuration;
        // amount of time the lockup period lasts
        uint256 lockupDuration;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
