// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

uint8 constant FOREX_DECIMALS = 8;
uint8 constant ETH_DECIMALS = 18;

library Tokens {
    /// @notice Returns the key for the unsorted `tokenA` and `tokenB`
    function keyForUnsortedPair(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address sortedA, address sortedTokenB) = sortTokens(tokenA, tokenB);
        return keyForSortedPair(sortedA, sortedTokenB);
    }

    /// @notice Returns the key for the sorted `tokenA` and `tokenB`
    function keyForSortedPair(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB));
    }

    /// @notice Returns the sorted `tokenA` and `tokenB`, where sortedA < sortedB
    function sortTokens(address tokenA, address tokenB) internal pure returns (address sortedA, address sortedB) {
        (sortedA, sortedB) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
