// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {iZERO} from "./Constants.sol";

library PRBMathExtra {
    /// @notice Returns the greater of two numbers `a` and `b`
    function max(UD60x18 a, UD60x18 b) internal pure returns (UD60x18) {
        return a > b ? a : b;
    }

    /// @notice Returns the lesser of two numbers `a` and `b`
    function min(UD60x18 a, UD60x18 b) internal pure returns (UD60x18) {
        return a > b ? b : a;
    }

    /// @notice Returns the greater of two numbers `a` and `b`
    function max(SD59x18 a, SD59x18 b) internal pure returns (SD59x18) {
        return a > b ? a : b;
    }

    /// @notice Returns the lesser of two numbers `a` and `b`
    function min(SD59x18 a, SD59x18 b) internal pure returns (SD59x18) {
        return a > b ? b : a;
    }

    /// @notice Returns the sum of `a` and `b`
    function add(UD60x18 a, SD59x18 b) internal pure returns (UD60x18) {
        return b < iZERO ? sub(a, -b) : a + b.intoUD60x18();
    }

    /// @notice Returns the difference of `a` and `b`
    function sub(UD60x18 a, SD59x18 b) internal pure returns (UD60x18) {
        return b < iZERO ? add(a, -b) : a - b.intoUD60x18();
    }
}
