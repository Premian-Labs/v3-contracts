// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";

interface IUniswapV3Adapter is IOracleAdapter {
    /// @notice Returns the address of the Uniswap V3 factory
    /// @dev This value is assigned during deployment and cannot be changed
    /// @return The address of the Uniswap V3 factory
    function factory() external view returns (IUniswapV3Factory);

    /// @notice Returns the period used for the TWAP calculation
    /// @return The period used for the TWAP
    function period() external view returns (uint32);

    /// @notice Returns the cardinality per minute used for adding support to pairs
    /// @return The cardinality per minute used for increase cardinality calculations
    function cardinalityPerMinute() external view returns (uint256);

    /// @notice Returns the target observation cardinality for pools
    /// @return The target observation cardinality for pools
    function targetCardinality() external view returns (uint16);

    /// @notice Returns the approximate gas cost per each increased cardinality
    /// @return The gas cost per cardinality increase
    function gasPerCardinality() external view returns (uint256);

    /// @notice Returns the approximate gas cost to add support for a new pool internally
    /// @return The gas cost to support a new pool
    function gasToSupportPool() external view returns (uint256);

    /// @notice Returns all supported fee tiers
    /// @return The supported fee tiers
    function supportedFeeTiers() external view returns (uint24[] memory);

    /// @notice When a pair is added to the oracle adapter, we will prepare all deployed pools for the pair. It could happen that
    ///         pools are added for the pair at a later stage, and we can't be sure if those pools will be configured correctly.
    ///         In this case, if a pool has an insufficient observation cardinality, `quote` and `quoteFrom` will revert.
    ///         This functions returns this list of pools known to be prepared.
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return The list of pools that will be used for quoting
    function poolsForPair(
        address tokenA,
        address tokenB
    ) external view returns (address[] memory);

    /// @notice Sets the period to be used for the TWAP calculation
    /// @param newPeriod The new period
    function setPeriod(uint32 newPeriod) external;

    /// @notice Sets the cardinality per minute to be used when increasing observation cardinality at the moment of adding support for pairs
    /// @param newCardinalityPerMinute The new cardinality per minute
    function setCardinalityPerMinute(uint256 newCardinalityPerMinute) external;

    /// @notice Inserts a new fee tier
    /// @param feeTier The new fee tier to add
    function insertFeeTier(uint24 feeTier) external;
}
