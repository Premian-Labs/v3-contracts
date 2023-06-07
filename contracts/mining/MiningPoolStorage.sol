// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

library MiningPoolStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.mining.MiningPool");

    struct Layout {
        uint8 baseDecimals;
        address base;
        address quote;
        address priceRepository;
        address paymentSplitter;
        // percentage of the asset spot price used to set the strike price
        UD60x18 discount;
        // percentage of the intrinsic value that is reduced after lockup period (ie 80% penalty (0.80e18), means the
        // long holder receives 20% of the options intrinsic value, the remaining 80% is refunded).
        UD60x18 penalty;
        // amount of time the option lasts (in seconds)
        uint256 expiryDuration;
        // amount of time the exercise period lasts (in seconds)
        uint256 exerciseDuration;
        // amount of time the lockup period lasts (in seconds)
        uint256 lockupDuration;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
