// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

interface IUniswapV3AdapterInternal {
    /// @notice Thrown when cardinality per minute has not been set
    error UniswapV3Adapter__CardinalityPerMinuteNotSet();

    /// @notice Thrown when trying to add an existing fee tier
    error UniswapV3Adapter__FeeTierExists(uint24 feeTier);

    /// @notice Thrown if the oldest observation is less than the TWAP period
    error UniswapV3Adapter__InsufficientObservationPeriod(
        uint32 oldestObservation,
        uint32 period
    );

    /// @notice Thrown when trying to add an invalid fee tier
    error UniswapV3Adapter__InvalidFeeTier(uint24 feeTier);

    /// @notice Thrown when the time ranges are not valid
    error UniswapV3Adapter__InvalidTimeRange(uint256 start, uint256 end);

    /// @notice Thrown when current observation cardinality is below target cardinality
    error UniswapV3Adapter__ObservationCardinalityTooLow(
        uint16 currentCardinality,
        uint16 targetCardinality
    );

    /// @notice Thrown when period has not been set
    error UniswapV3Adapter__PeriodNotSet();

    /// @notice Emitted when a new period is set
    /// @param period The new period
    event UpdatedPeriod(uint256 period);

    /// @notice Emitted when a new cardinality per minute is set
    /// @param cardinalityPerMinute The new cardinality per minute
    event UpdatedCardinalityPerMinute(uint256 cardinalityPerMinute);

    /// @notice Emitted when support is updated (added or modified) for a new pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param pools The pools that were prepared to support the pair
    event UpdatedPoolsForPair(address tokenA, address tokenB, address[] pools);
}
