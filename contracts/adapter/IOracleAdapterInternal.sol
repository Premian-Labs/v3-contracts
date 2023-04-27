// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

interface IOracleAdapterInternal {
    /// @notice Thrown when attempting to increase array size
    error OracleAdapter__ArrayCannotExpand(uint256 arrayLength, uint256 size);

    /// @notice Thrown when the target is zero or before the current block timestamp
    error OracleAdapter__InvalidTarget(uint256 target, uint256 blockTimestamp);

    /// @notice Thrown when the price is non-positive
    error OracleAdapter__InvalidPrice(int256 price);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error OracleAdapter__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported
    error OracleAdapter__PairNotSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to add pair where addresses are the same
    error OracleAdapter__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error OracleAdapter__ZeroAddress();
}
