// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IUniswapV3AdapterInternal} from "./IUniswapV3AdapterInternal.sol";

library UniswapV3AdapterStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.UniswapV3Adapter");

    struct Layout {
        uint8 cardinalityPerMinute;
        uint16 targetCardinality;
        uint32 period;
        uint24[] feeTiers;
        mapping(bytes32 => address[]) poolsForPair;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
