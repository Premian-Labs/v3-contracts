// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation
abstract contract OracleAdapter is IOracleAdapter {
    using SafeCast for int8;

    /// @notice Scales `amount` by `factor`
    function _scale(uint256 amount, int8 factor) internal pure returns (uint256) {
        if (factor == 0) return amount;

        if (factor < 0) {
            return amount / (10 ** (-factor).toUint256());
        } else {
            return amount * (10 ** factor.toUint256());
        }
    }

    /// @notice Revert if `target` is zero or after block.timestamp
    function _revertIfTargetInvalid(uint256 target) internal view {
        if (target == 0 || target > block.timestamp) revert OracleAdapter__InvalidTarget(target, block.timestamp);
    }

    /// @notice Revert if `price` is zero or negative
    function _revertIfPriceInvalid(int256 price) internal pure {
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
    }

    /// @notice Revert if `tokenA` has same address as `tokenB`
    function _revertIfTokensAreSame(address tokenA, address tokenB) internal pure {
        if (tokenA == tokenB) revert OracleAdapter__TokensAreSame(tokenA, tokenB);
    }

    /// @notice Revert if `tokenA` or `tokenB` are null addresses
    function _revertIfZeroAddress(address tokenA, address tokenB) internal pure {
        if (tokenA == address(0) || tokenB == address(0)) revert OracleAdapter__ZeroAddress();
    }
}
