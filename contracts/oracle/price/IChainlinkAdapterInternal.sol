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
        // Will use tokenA/USD, tokenB/ETH and ETH/USD feeds
        A_USD_ETH_B,
        // Will use tokenA/ETH, tokenB/USD and ETH/USD feeds
        A_ETH_USD_B,
        // Will use a token/USD, BTC/USD, WBTC/BTC feeds
        TOKEN_USD_BTC_WBTC
    }

    enum ConversionType {
        ToBtc, // Token -> BTC
        ToUsd, // Token -> USD
        ToEth, // Token -> ETH
        ToUsdToToken, // Token -> USD -> Token
        ToEthToToken // Token -> ETH -> Token
    }

    /// @notice Thrown when the price after the target time is stale
    error ChainlinkAdapter__PriceAfterTargetIsStale();

    /// @notice Emitted when the adapter updates the pricing path for a pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param path The new path
    event UpdatedPathForPair(address tokenA, address tokenB, PricingPath path);

    /// @notice Emitted when new Chainlink price feed mappings are registered
    /// @param args The arguments for the new mappings
    event FeedMappingsRegistered(FeedMappingArgs[] args);
}
