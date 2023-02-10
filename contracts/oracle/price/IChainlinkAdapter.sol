// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {FeedRegistryInterface, IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title An implementation of IOracleAdapter that uses Chainlink feeds
/// @notice This oracle will attempt to use all available feeds to determine prices between pairs
/// @notice derived from https://github.com/Mean-Finance/oracles
interface IChainlinkAdapter is IOracleAdapter {
    /// @notice Returns the pricing plan that will be used when quoting the given pair
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @return The pricing plan that will be used
    function planForPair(
        address tokenA,
        address tokenB
    ) external view returns (IChainlinkAdapterInternal.PricingPlan);

    /// @notice Returns the mapping of the given token, if it exists. If it doesn't, then the original token is returned
    /// @return If it exists, the mapping is returned. Otherwise, the original token is returned
    function mappedToken(address token) external view returns (address);

    /// @notice Adds new token mappings
    /// @param addresses The addresses of the tokens
    /// @param mappings The addresses of their mappings
    function addMappings(
        address[] calldata addresses,
        address[] calldata mappings
    ) external;

    /// @notice Returns max duration between price updates before the oracle price is considered stale
    /// @return max duration between price updates
    function maxDelay() external pure returns (uint32);

    /// @notice Returns the Chainlink feed registry address
    /// @return Chainlink feed registry address
    function feedRegistry() external view returns (address);
}
