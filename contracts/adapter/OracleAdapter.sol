// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

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

    /// @notice Resizes the `array` to `size`, reverts if size > array.length
    function _resizeArray(address[] memory array, uint256 size) internal pure {
        if (array.length == size) return;
        if (array.length < size)
            revert OracleAdapter__ArrayCannotExpand(array.length, size);

        assembly {
            mstore(array, size)
        }
    }

    /// @notice Resizes the `array` to `size`, reverts if size > array.length
    function _resizeArray(uint8[] memory array, uint256 size) internal pure {
        if (array.length == size) return;
        if (array.length < size)
            revert OracleAdapter__ArrayCannotExpand(array.length, size);

        assembly {
            mstore(array, size)
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
