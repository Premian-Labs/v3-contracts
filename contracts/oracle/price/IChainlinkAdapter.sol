// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title An implementation of IOracleAdapter that uses Chainlink feeds
/// @notice This oracle adapter will attempt to use all available feeds to determine
///         prices between pairs
/// @notice derived from https://github.com/Mean-Finance/oracles
interface IChainlinkAdapter is IOracleAdapter {
    /// @notice Returns the pricing path that will be used when quoting the given pair
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @return The pricing path that will be used
    function pathForPair(
        address tokenA,
        address tokenB
    ) external view returns (IChainlinkAdapterInternal.PricingPath);

    /// @notice Registers mappings of ERC20 token, and denomination (ETH, or USD) to Chainlink feed
    /// @param args The arguments for the new mappings
    function batchRegisterFeedMappings(
        IChainlinkAdapterInternal.FeedMappingArgs[] memory args
    ) external;

    /// @notice Returns the Chainlink feed for the given pair
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @return The Chainlink feed address
    function feed(
        address tokenA,
        address tokenB
    ) external view returns (address);
}
