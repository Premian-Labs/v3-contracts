// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

/// @title The interface for an oracle adapter that provides price quotes
/// @notice These methods allow users to add support for pairs, and then ask for quotes
/// @notice derived from https://github.com/Mean-Finance/oracles
interface IOracleAdapter {
    enum AdapterType {
        NONE,
        CHAINLINK,
        UNISWAP_V3
    }

    /// @notice Returns whether the pair has already been added to the adapter and if it
    ///         supports the path required for the pair
    ///         (true, true): Pair is fully supported
    ///         (false, true): Pair is not supported, but can be added
    ///         (false, false): Pair cannot be supported
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return isCached True if the pair has been cached, false otherwise
    /// @return hasPath True if the pair has a valid path, false otherwise
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool isCached, bool hasPath);

    /// @notice Maps the given token pair to a path or updates an existing mapping. This function will
    ///         let the adapter take some actions to configure the pair, in preparation for future quotes.
    ///         Can be called many times in order to let the adapter re-configure for a new context
    /// @dev Will revert if pair cannot be supported or has already been added. tokenA and tokenB may be
    ///      passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    function upsertPair(address tokenA, address tokenB) external;

    /// @notice Returns a quote, based on the given token pair
    /// @dev Will revert if pair isn't supported
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @return Spot price of base denominated in quote token | 18 decimals
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18);

    /// @notice Returns a quote closest to the target timestamp, based on the given token pair
    /// @dev Will revert if pair isn't supported
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @param target Reference timestamp of the quote
    /// @return Historical price of base denominated in quote token | 18 decimals
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (uint256);

    /// @notice Describes the pricing path used to convert the token to ETH
    /// @param token The token from where the pricing path starts
    /// @return adapterType The type of adapter
    /// @return path The path required to convert the token to ETH
    /// @return decimals The decimals of each token in the path
    function describePricingPath(
        address token
    )
        external
        view
        returns (
            AdapterType adapterType,
            address[][] memory path,
            uint8[] memory decimals
        );
}
