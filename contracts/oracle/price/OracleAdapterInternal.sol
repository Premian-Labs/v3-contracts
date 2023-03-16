// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IOracleAdapterInternal} from "./IOracleAdapterInternal.sol";

/// @title Base oracle adapter internal implementation
abstract contract OracleAdapterInternal is IOracleAdapterInternal {
    using SafeCast for int256;

    function _scale(
        uint256 amount,
        int256 factor
    ) internal pure returns (uint256) {
        if (factor < 0) {
            return amount / (10 ** (-factor).toUint256());
        } else {
            return amount * (10 ** factor.toUint256());
        }
    }

    function _ensureTargetNonZero(uint256 target) internal view {
        if (target == 0 || target > block.timestamp)
            revert OracleAdapter__InvalidTarget();
    }

    function _ensurePriceNonZero(int256 price) internal pure {
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
    }
}
