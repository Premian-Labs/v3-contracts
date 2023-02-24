// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title TokenSorting library
/// @notice Provides functions to sort tokens easily
/// @notice derived from https://github.com/Mean-Finance/oracles
library TokenSorting {
    /// @notice Takes two tokens, and returns them sorted
    /// @param tokenA One of the tokens
    /// @param tokenB The other token
    /// @return _tokenA The first of the tokens
    /// @return _tokenB The second of the tokens
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address _tokenA, address _tokenB) {
        (_tokenA, _tokenB) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }
}
