// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {FeedRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
interface IChainlinkAdapterInternal {
    /// @notice Thrown when the price is non-positive
    error Oracle__InvalidPrice();

    /// @notice Thrown when the last price update was too long ago
    error Oracle__LastUpdateIsTooOld();

    /// @notice Thrown when the input for adding mappings in invalid
    error Oracle__InvalidMappingsInput();

    /// @notice The plan that will be used to calculate quotes for a given pair
    enum PricingPlan {
        // There is no plan calculated
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

    /// @notice Emitted when the oracle updated the pricing plan for a pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param plan The new plan
    event UpdatedPlanForPair(address tokenA, address tokenB, PricingPlan plan);

    /// @notice Emitted when new tokens are considered USD
    /// @param tokens The new tokens
    event TokensConsideredUSD(address[] tokens);

    /// @notice Emitted when tokens should no longer be considered USD
    /// @param tokens The tokens to no longer consider USD
    event TokensNoLongerConsideredUSD(address[] tokens);

    /// @notice Emitted when new mappings are added
    /// @param tokens The tokens
    /// @param mappings Their new mappings
    event MappingsAdded(address[] tokens, address[] mappings);
}
