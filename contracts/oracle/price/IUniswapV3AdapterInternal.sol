// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

/// @notice derived from https://github.com/Mean-Finance/oracles and
///         https://github.com/Mean-Finance/uniswap-v3-oracle
interface IUniswapV3AdapterInternal {
    /// @notice Thrown when trying to add an existing fee tier
    error UniswapV3Adapter__FeeTierExists(uint24 feeTier);

    /// @notice Thrown if the oldest observation is less than the TWAP period
    error UniswapV3Adapter__InsufficientObservationPeriod();

    /// @notice Thrown when trying to add an invalid fee tier
    error UniswapV3Adapter__InvalidFeeTier(uint24 feeTier);

    /// @notice Thrown when trying to set an invalid cardinality
    error UniswapV3Adapter__InvalidCardinalityPerMinute();

    /// @notice Thrown when the time ranges are not valid
    error UniswapV3Adapter__InvalidTimeRange();

    /// @notice Thrown when current oberservation cardinality has not been set
    error UniswapV3Adapter__ObservationCardinalityNotSet();

    /// @notice Thrown when current oberservation cardinality is below target cardinality
    error UniswapV3Adapter__ObservationCardinalityTooLow();

    /// @notice Thrown when period has not been set
    error UniswapV3Adapter__PeriodNotSet();

    /// @notice Emitted when a new period is set
    /// @param period The new period
    event PeriodChanged(uint32 period);

    /// @notice Emitted when a new cardinality per minute is set
    /// @param cardinalityPerMinute The new cardinality per minute
    event CardinalityPerMinuteChanged(uint8 cardinalityPerMinute);

    /// @notice Emitted when support is updated (added or modified) for a new pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param pools The pools that were prepared to support the pair
    event UpdatedPoolsForPair(address tokenA, address tokenB, address[] pools);
}
