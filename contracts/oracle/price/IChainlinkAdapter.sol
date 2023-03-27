// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {IOracleAdapter} from "./IOracleAdapter.sol";
import {IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";

/// @title An implementation of IOracleAdapter that uses Chainlink feeds
/// @notice This oracle adapter will attempt to use all available feeds to determine
///         prices between pairs
interface IChainlinkAdapter is IOracleAdapter {
    /// @notice Returns the pricing path that will be used when quoting the given pair
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return The pricing path that will be used
    function pricingPath(
        address tokenA,
        address tokenB
    ) external view returns (IChainlinkAdapterInternal.PricingPath);
}
