// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title The interface for an oracle that provides price quotes
/// @notice These methods allow users to add support for pairs, and then ask for quotes
/// @notice derived from https://github.com/Mean-Finance/oracles
interface IOracleAdapter {
    /// @notice Thrown when trying to add pair where addresses are the same
    error Oracle__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that has already been added
    error Oracle__PairAlreadySupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error Oracle__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported yet
    error Oracle__PairNotSupportedYet(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error Oracle__ZeroAddress();

    /// @notice Returns whether this oracle can support the given pair of tokens
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @return Whether the given pair of tokens can be supported by the oracle
    function canSupportPair(
        address tokenA,
        address tokenB
    ) external view returns (bool);

    /// @notice Returns whether this oracle is already supporting the given pair of tokens
    /// @dev tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    /// @return Whether the given pair of tokens is already being supported by the oracle
    function isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) external view returns (bool);

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

    /// @notice Add or reconfigures the support for a given pair. This function will let the oracle take some actions to configure the
    ///         pair, in preparation for future quotes. Can be called many times in order to let the oracle re-configure for a new
    ///         context
    /// @dev Will revert if pair cannot be supported or has already been added. tokenA and tokenB may be passed in either tokenA/tokenB
    ///      or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    function addOrModifySupportForPair(address tokenA, address tokenB) external;

    /// @notice Adds support for a given pair if the oracle didn't support it already. If called for a pair that is already supported,
    ///         the transaction will revert. This function will let the oracle take some actions to configure the pair, in preparation
    ///         for future quotes
    /// @dev Will revert if pair cannot be supported or has already been added. tokenA and tokenB may be passed in either tokenA/tokenB
    ///      or tokenB/tokenA order
    /// @param tokenA The exchange token (base token)
    /// @param tokenB The token to quote against (quote token)
    function addSupportForPairIfNeeded(address tokenA, address tokenB) external;
}
