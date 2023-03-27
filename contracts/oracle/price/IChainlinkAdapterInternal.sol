// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

interface IChainlinkAdapterInternal {
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
        TO_BTC, // Token -> BTC
        TO_USD, // Token -> USD
        TO_ETH, // Token -> ETH
        TO_USD_TO_TOKEN, // Token -> USD -> Token
        TO_ETH_TO_TOKEN // Token -> ETH -> Token
    }

    /// @notice Thrown when the getRoundData call reverts without a reason
    error ChainlinkAdapter__GetRoundDataCallReverted(bytes data);

    /// @notice Thrown when the lastRoundData call reverts without a reason
    error ChainlinkAdapter__LatestRoundDataCallReverted(bytes data);

    /// @notice Thrown when the price after the target time is stale
    error ChainlinkAdapter__PriceAfterTargetIsStale();

    /// @notice Emitted when the adapter updates the pricing path for a pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param path The new path
    event UpdatedPathForPair(address tokenA, address tokenB, PricingPath path);
}
