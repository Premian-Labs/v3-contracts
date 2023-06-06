// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

library PriceRepositoryStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.mining.PriceRepository");

    struct Layout {
        address keeper;
        // price recorded at 8AM UTC each day
        mapping(address base => mapping(address quote => mapping(uint256 timestamp => UD60x18 price))) dailyOpenPrice;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
