// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @title Base oracle adapter internal implementation
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapterInternal {
    /// @notice Thrown when the target is zero or before the current block timestamp
    error OracleAdapter__InvalidTarget();

    /// @notice Thrown when the price is non-positive
    error OracleAdapter__InvalidPrice(int256 price);

    /// @notice Thrown when trying to add pair where addresses are the same
    error OracleAdapter__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error OracleAdapter__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported
    error OracleAdapter__PairNotSupported(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error OracleAdapter__ZeroAddress();

    function _ensureTargetNonZero(uint256 target) internal view {
        if (target == 0 || target > block.timestamp)
            revert OracleAdapter__InvalidTarget();
    }

    function _ensurePriceNonZero(int256 price) internal pure {
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
    }
}
