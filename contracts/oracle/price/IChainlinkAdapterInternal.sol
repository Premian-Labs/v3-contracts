// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
interface IChainlinkAdapterInternal {
    struct DenominationMappingArgs {
        address token;
        address denomination;
    }

    struct FeedMappingArgs {
        address token;
        address denomination;
        address feed;
    }

    /// @notice The path that will be used to calculate quotes for a given pair
    enum PricingPath {
        // There is no path calculated
        NONE,
        // Will use the ETH/USD feed
        ETH_USD_PAIR,
        // Will use a token/USD feed
        TOKEN_USD_PAIR,
        // Will use a token/ETH feed
        TOKEN_ETH_PAIR,
        // Will use tokenIn/USD and tokenOut/USD feeds
        TOKEN_TO_USD_TO_TOKEN_PAIR,
        // Will use tokenIn/ETH and tokenOut/ETH feeds
        TOKEN_TO_ETH_TO_TOKEN_PAIR,
        // Will use tokenA/USD, tokenB/ETH and ETH/USD feeds
        TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B,
        // Will use tokenA/ETH, tokenB/USD and ETH/USD feeds
        TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
        // Used then tokenA is the same as tokenB
        SAME_TOKENS
    }

    /// @notice Thrown when the price is non-positive
    error Oracle__InvalidPrice();

    /// @notice Thrown when the last price update was too long ago
    error Oracle__LastUpdateIsTooOld();

    /// @notice Thrown when the input array lengths do not match
    error Oracle__InvalidArrayLengths();

    /// @notice Emitted when the oracle updated the pricing path for a pair
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @param path The new path
    event UpdatedPathForPair(address tokenA, address tokenB, PricingPath path);

    /// @notice Emitted when new Chainlink denomination mappings are registered
    /// @param args The arguments for the new mappings
    event DenominationMappingsRegistered(DenominationMappingArgs[] args);

    /// @notice Emitted when new Chainlink price feed mappings are registered
    /// @param args The arguments for the new mappings
    event FeedMappingsRegistered(FeedMappingArgs[] args);
}
