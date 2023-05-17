// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IOracleAdapter {
    /// @notice The type of adapter
    enum AdapterType {
        NONE,
        CHAINLINK,
        UNISWAP_V3
    }

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

    /// @notice Returns whether the pair has already been added to the adapter and if it supports the path required for the pair
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

    /// @notice Stores or updates the given token pair data provider configuration. This function will let the adapter take some
    ///         actions to configure the pair, in preparation for future quotes. Can be called many times in order to let the adapter
    ///         re-configure for a new context
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    function upsertPair(address tokenA, address tokenB) external;

    /// @notice Returns a quote, based on the given token pair
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @return Spot price of base denominated in quote token (18 decimals)
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18);

    /// @notice Returns a quote closest to the target timestamp, based on the given token pair
    /// @param tokenIn The exchange token (base token)
    /// @param tokenOut The token to quote against (quote token)
    /// @param target Reference timestamp of the quote
    /// @return Historical price of base denominated in quote token (18 decimals)
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (UD60x18);

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
