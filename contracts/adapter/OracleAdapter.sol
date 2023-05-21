// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.20;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation
abstract contract OracleAdapter is IOracleAdapter {
    using SafeCast for int8;

    /// @notice Scales `amount` by `factor`
    function _scale(
        uint256 amount,
        int8 factor
    ) internal pure returns (uint256) {
        if (factor == 0) return amount;

        if (factor < 0) {
            return amount / (10 ** (-factor).toUint256());
        } else {
            return amount * (10 ** factor.toUint256());
        }
    }

    /// @notice Revert if `target` is zero or after block.timestamp
    function _revertIfTargetInvalid(uint256 target) internal view {
        if (target == 0 || target > block.timestamp)
            revert OracleAdapter__InvalidTarget(target, block.timestamp);
    }

    /// @notice Revert if `price` is zero or negative
    function _revertIfPriceInvalid(int256 price) internal pure {
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
    }
}
