// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

/// @title Base oracle adapter internal implementation
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapterInternal {
    using SafeCast for int256;

    int256 internal constant ETH_DECIMALS = 18;

    /// @notice Thrown when attempting to increase array size
    error OracleAdapter__ArrayCannotExpand();

    /// @notice Thrown when the target is zero or before the current block timestamp
    error OracleAdapter__InvalidTarget();

    /// @notice Thrown when the price is non-positive
    error OracleAdapter__InvalidPrice(int256 price);

    /// @notice Thrown when trying to add pair where addresses are the same
    error OracleAdapter__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when trying to add support for a pair that cannot be supported
    error OracleAdapter__PairCannotBeSupported(address tokenA, address tokenB);

    /// @notice Thrown when trying to execute a quote with a pair that isn't supported
    error OracleAdapter__PairNotSupported(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error OracleAdapter__ZeroAddress();

    function _keyForUnsortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address sortedA, address sortedTokenB) = _sortTokens(tokenA, tokenB);

        return _keyForSortedPair(sortedA, sortedTokenB);
    }

    /// @dev Expects `tokenA` and `tokenB` to be sorted
    function _keyForSortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB));
    }

    function _scale(
        uint256 amount,
        int256 factor
    ) internal pure returns (uint256) {
        if (factor == 0) return amount;

        if (factor < 0) {
            return amount / (10 ** (-factor).toUint256());
        } else {
            return amount * (10 ** factor.toUint256());
        }
    }

    function _sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address _tokenA, address _tokenB) {
        (_tokenA, _tokenB) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
    }

    function _resizeArray(address[] memory array, uint256 size) internal pure {
        if (array.length == size) return;
        if (array.length < size) revert OracleAdapter__ArrayCannotExpand();

        assembly {
            mstore(array, size)
        }
    }

    function _resizeArray(uint8[] memory array, uint256 size) internal pure {
        if (array.length == size) return;
        if (array.length < size) revert OracleAdapter__ArrayCannotExpand();

        assembly {
            mstore(array, size)
        }
    }

    function _ensureTargetNonZero(uint256 target) internal view {
        if (target == 0 || target > block.timestamp)
            revert OracleAdapter__InvalidTarget();
    }

    function _ensurePricePositive(int256 price) internal pure {
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
    }
}
