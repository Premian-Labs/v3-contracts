// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

int256 constant FOREX_DECIMALS = 8;
int256 constant ETH_DECIMALS = 18;

library Tokens {
    function keyForUnsortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address sortedA, address sortedTokenB) = sortTokens(tokenA, tokenB);
        return keyForSortedPair(sortedA, sortedTokenB);
    }

    /// @dev Expects `tokenA` and `tokenB` to be sorted
    function keyForSortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB));
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address _tokenA, address _tokenB) {
        (_tokenA, _tokenB) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }
}
