// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.20;

uint8 constant FOREX_DECIMALS = 8;
uint8 constant ETH_DECIMALS = 18;

library Tokens {
    /// @notice Returns the key for the unsorted `tokenA` and `tokenB`
    function keyForUnsortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address sortedA, address sortedTokenB) = sortTokens(tokenA, tokenB);
        return keyForSortedPair(sortedA, sortedTokenB);
    }

    /// @notice Returns the key for the sorted `tokenA` and `tokenB`
    function keyForSortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB));
    }

    /// @notice Returns the sorted `tokenA` and `tokenB`, where _tokenA < _tokenB
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address _tokenA, address _tokenB) {
        (_tokenA, _tokenB) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }
}
