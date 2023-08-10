// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {IFeedRegistry} from "../IFeedRegistry.sol";
import {IPriceRepository} from "../../adapter/IPriceRepository.sol";

interface IChainlinkAdapter is IOracleAdapter, IFeedRegistry, IPriceRepository {
    // Note : The following enums do not follow regular style guidelines for the purpose of easier readability

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

    /// @notice The conversion type used when determining the token pair pricing path
    enum ConversionType {
        TO_BTC, // Token -> BTC
        TO_USD, // Token -> USD
        TO_ETH, // Token -> ETH
        TO_USD_TO_TOKEN, // Token -> USD -> Token
        TO_ETH_TO_TOKEN // Token -> ETH -> Token
    }

    /// @notice Thrown when the getRoundData call reverts without a reason
    error ChainlinkAdapter__GetRoundDataCallReverted(bytes data);

    /// @notice Thrown when the denomination is invalid
    error ChainlinkAdapter__InvalidDenomination(address denomination);

    /// @notice Thrown when the lastRoundData call reverts without a reason
    error ChainlinkAdapter__LatestRoundDataCallReverted(bytes data);

    /// @notice Thrown when a price at or to the left of target is not found
    error ChainlinkAdapter__PriceAtOrLeftOfTargetNotFound(address token, address denomination, uint256 target);

    /// @notice Thrown when price left of target is stale
    error ChainlinkAdapter__PriceLeftOfTargetStale(uint256 updatedAt, uint256 target);

    /// @notice Emitted when the adapter updates the pricing path for a pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param path The new path
    event UpdatedPathForPair(address tokenA, address tokenB, PricingPath path);

    struct BinarySearchDataInternal {
        int256 leftPrice;
        uint256 leftUpdatedAt;
        int256 rightPrice;
        uint256 rightUpdatedAt;
    }

    /// @notice Returns the pricing path that will be used when quoting the given pair
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return The pricing path that will be used
    function pricingPath(address tokenA, address tokenB) external view returns (PricingPath);
}
