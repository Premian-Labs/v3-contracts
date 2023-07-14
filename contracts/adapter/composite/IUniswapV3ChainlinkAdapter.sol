// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IUniswapV3ChainlinkAdapter {
    /// @notice Thrown when the token is the wrapped native token
    error UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative();
}
