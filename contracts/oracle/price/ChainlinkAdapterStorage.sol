// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {FOREX_DECIMALS, ETH_DECIMALS} from "./Tokens.sol";
import {IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";

library ChainlinkAdapterStorage {
    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.ChainlinkAdapter");

    struct Layout {
        mapping(bytes32 => IChainlinkAdapterInternal.PricingPath) pathForPair;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function formatRoundId(
        uint16 phaseId,
        uint64 aggregatorRoundId
    ) internal pure returns (uint80) {
        return uint80((uint256(phaseId) << 64) | aggregatorRoundId);
    }

    function parseRoundId(
        uint256 roundId
    ) internal pure returns (uint16 phaseId, uint64 aggregatorRoundId) {
        phaseId = uint16(roundId >> 64);
        aggregatorRoundId = uint64(roundId);
    }

    function decimalsFactor(
        IChainlinkAdapterInternal.PricingPath path
    ) internal pure returns (int256) {
        if (
            path == IChainlinkAdapterInternal.PricingPath.ETH_USD ||
            path == IChainlinkAdapterInternal.PricingPath.TOKEN_USD ||
            path == IChainlinkAdapterInternal.PricingPath.TOKEN_USD_TOKEN ||
            path == IChainlinkAdapterInternal.PricingPath.A_USD_ETH_B ||
            path == IChainlinkAdapterInternal.PricingPath.A_ETH_USD_B ||
            path == IChainlinkAdapterInternal.PricingPath.TOKEN_USD_BTC_WBTC
        ) {
            return ETH_DECIMALS - FOREX_DECIMALS;
        }

        return 0;
    }

    function isUSD(address token) internal pure returns (bool) {
        return token == Denominations.USD;
    }

    function isETH(address token) internal pure returns (bool) {
        return token == Denominations.ETH;
    }
}
