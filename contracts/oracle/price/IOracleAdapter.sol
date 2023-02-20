// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title The interface for an oracle adapter that provides price quotes
/// @notice These methods allow users to add support for pairs, and then ask for quotes
/// @notice derived from https://github.com/Mean-Finance/oracles
interface IOracleAdapter {
    /// @notice Returns whether the pair has already been added to the adapter and if it
    ///         supports the path required for the pair
    ///         (true, true): Pair is fully supported
    ///         (false, true): Pair is not supported, but can be added
    ///         (false, false): Pair cannot be supported
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
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
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    function upsertPair(address tokenA, address tokenB) external;

    /// @notice Returns a quote, based on the given token pair. If the pair has not been added
    ///         the adapter will attempt to add it
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @return Spot price of base denominated in quote token
    function tryQuote(
        address tokenIn,
        address tokenOut
    ) external returns (uint256);

    /// @notice Returns a quote, based on the given token pair
    /// @dev Will revert if pair isn't supported
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @return Spot price of base denominated in quote token
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (uint256);
}
