// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";

library ChainlinkAdapterStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.ChainlinkAdapter");

    struct Layout {
        mapping(bytes32 key => IChainlinkAdapter.PricingPath) pricingPath;
        mapping(address token => EnumerableSet.AddressSet tokens) pairedTokens;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function formatRoundId(uint16 phaseId, uint64 aggregatorRoundId) internal pure returns (uint80) {
        return uint80((uint256(phaseId) << 64) | aggregatorRoundId);
    }

    function parseRoundId(uint256 roundId) internal pure returns (uint16 phaseId, uint64 aggregatorRoundId) {
        phaseId = uint16(roundId >> 64);
        aggregatorRoundId = uint64(roundId);
    }

    function isUSD(address token) internal pure returns (bool) {
        return token == Denominations.USD;
    }

    function isBTC(address token) internal pure returns (bool) {
        return token == Denominations.BTC;
    }

    function isETH(address token) internal pure returns (bool) {
        return token == Denominations.ETH;
    }
}
