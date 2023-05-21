// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.20;

library UniswapV3AdapterStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.UniswapV3Adapter");

    struct Layout {
        // Assumes that the UniswapV3 pool will have at least one observation per block (but no more than one
        // observation per second, see note below) for the TWAP period to ensure that no observations are missed.
        // target_cardinality = period * cardinality_per_minute / 60
        uint16 targetCardinality;
        // TWAP period (in seconds)
        uint32 period;
        // Proxy for max observations per minute. Larger cardinality per minute values will provide a longer window of
        // availability for historical price quotes.
        // NOTE: UniswapV3 pools only record observations if an observation has not been made at the current timestamp,
        // therefore, pools will store at most 60 observations per minute.
        uint256 cardinalityPerMinute;
        uint24[] feeTiers;
        mapping(bytes32 key => address[] pools) poolsForPair;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
