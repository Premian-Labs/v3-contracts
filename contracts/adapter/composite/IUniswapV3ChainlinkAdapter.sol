// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IUniswapV3ChainlinkAdapter {
    /// @notice Thrown when the token is the wrapped native token
    error UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative();
}
