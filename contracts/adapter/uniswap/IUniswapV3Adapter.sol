// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";

interface IUniswapV3Adapter is IOracleAdapter {
    /// @notice Thrown when cardinality per minute has not been set
    error UniswapV3Adapter__CardinalityPerMinuteNotSet();

    /// @notice Thrown when trying to add an existing fee tier
    error UniswapV3Adapter__FeeTierExists(uint24 feeTier);

    /// @notice Thrown if the oldest observation is less than the TWAP period
    error UniswapV3Adapter__InsufficientObservationPeriod(uint32 oldestObservation, uint32 period);

    /// @notice Thrown when trying to add an invalid fee tier
    error UniswapV3Adapter__InvalidFeeTier(uint24 feeTier);

    /// @notice Thrown when the time ranges are not valid
    error UniswapV3Adapter__InvalidTimeRange(uint256 start, uint256 end);

    /// @notice Thrown when current observation cardinality is below target cardinality
    error UniswapV3Adapter__ObservationCardinalityTooLow(uint16 currentCardinality, uint16 targetCardinality);

    /// @notice Thrown when tokens are unsorted
    error UniswapV3Adapter__TokensUnsorted(address token0, address token1);

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

    /// @notice When a pair is added to the oracle adapter, we will prepare all deployed pools for the pair. It could
    ///         happen that pools are added for the pair at a later stage, and we can't be sure if those pools will be
    ///         configured correctly. In this case, if a pool has an insufficient observation cardinality, `quote` and
    ///         `getPriceAt` will revert. This function returns this list of pools known to be prepared.
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return The list of pools that will be used for quoting
    function poolsForPair(address tokenA, address tokenB) external view returns (address[] memory);

    /// @notice Returns the address of the UniswapV3 factory
    /// @dev This value is assigned during deployment and cannot be changed
    /// @return The address of the UniswapV3 factory
    function getFactory() external view returns (IUniswapV3Factory);

    /// @notice Returns the TWAP period (seconds)
    /// @return The TWAP period (seconds)
    function getPeriod() external view returns (uint32);

    /// @notice Returns the cardinality per minute used for adding support to pairs
    /// @return The cardinality per minute
    function getCardinalityPerMinute() external view returns (uint256);

    /// @notice Returns the target cardinality
    /// @return The target cardinality
    function getTargetCardinality() external view returns (uint16);

    /// @notice Returns the approximate gas cost per each increased cardinality
    /// @return The gas cost per cardinality increase
    function getGasPerCardinality() external view returns (uint256);

    /// @notice Returns the approximate gas cost to add support for a new pool
    /// @return The gas cost to support a new pool
    function getGasToSupportPool() external view returns (uint256);

    /// @notice Returns all supported fee tiers
    /// @return The supported fee tiers
    function getSupportedFeeTiers() external view returns (uint24[] memory);

    /// @notice Sets the TWAP period (seconds)
    /// @param newPeriod The new TWAP period (seconds)
    function setPeriod(uint32 newPeriod) external;

    /// @notice Sets the cardinality per minute to be used when increasing observation cardinality at the moment of
    ///         adding support for pairs
    /// @param newCardinalityPerMinute The new cardinality per minute
    function setCardinalityPerMinute(uint256 newCardinalityPerMinute) external;

    /// @notice Inserts a new fee tier
    /// @param feeTier The new fee tier to add
    function insertFeeTier(uint24 feeTier) external;
}
