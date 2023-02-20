// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @notice derived from https://github.com/Mean-Finance/oracles
interface IChainlinkAdapterInternal {
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
        ETH_USD,
        // Will use a token/USD feed
        TOKEN_USD,
        // Will use a token/ETH feed
        TOKEN_ETH,
        // Will use tokenIn/USD and tokenOut/USD feeds
        TOKEN_USD_TOKEN,
        // Will use tokenIn/ETH and tokenOut/ETH feeds
        TOKEN_ETH_TOKEN,
        // Will use tokenA/USD, tokenB/ETH and ETH/USD feeds, if B = ETH, ETH -> B conversion is skipped
        A_USD_ETH_B,
        // Will use tokenA/ETH, tokenB/USD and ETH/USD feeds, if B = USD, USD -> B conversion is skipped
        A_ETH_USD_B,
        // Will use a token/WBTC feed
        TOKEN_WBTC
    }

    /// @notice Thrown when the last price update exceeds the max delay
    /// @param timestamp Current timestamp
    /// @param updatedAt Timestamp of the last price update
    error ChainlinkAdapter__PriceIsStale(uint256 timestamp, uint256 updatedAt);

    /// @notice Thrown when the round id exceeds the answered round id
    /// @param roundId Derived round id
    /// @param answeredInRound Round of last price update
    error ChainlinkAdapter__RoundIsStale(
        uint80 roundId,
        uint80 answeredInRound
    );

    /// @notice Emitted when the oracle updated the pricing path for a pair
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @param path The new path
    event UpdatedPathForPair(address tokenA, address tokenB, PricingPath path);

    /// @notice Emitted when new Chainlink price feed mappings are registered
    /// @param args The arguments for the new mappings
    event FeedMappingsRegistered(FeedMappingArgs[] args);
}
