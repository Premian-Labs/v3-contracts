// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Base oracle adapter internal implementation
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapterInternal {
    /// @notice Thrown when the price is non-positive
    error OracleAdapter__InvalidPrice(int256 price);

    /// @notice Thrown when trying to add pair where addresses are the same
    error OracleAdapter__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that has already been added
    error OracleAdapter__PairAlreadySupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error OracleAdapter__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported
    error OracleAdapter__PairNotSupported(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error OracleAdapter__ZeroAddress();

    /// @notice Add or reconfigures the support for a given pair. This function will let the oracle take some actions
    ///         to configure the pair, in preparation for future quotes. Can be called many times in order to let the oracle
    ///         re-configure for a new context
    /// @dev Will revert if pair cannot be supported. tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    function _addOrModifySupportForPair(
        address tokenA,
        address tokenB
    ) internal virtual;
}
