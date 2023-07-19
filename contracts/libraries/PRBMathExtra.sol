// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {UD50x28, uMAX_UD50x28} from "./UD50x28.sol";
import {SD49x28, uMAX_SD49x28} from "./SD49x28.sol";

import {iZERO, SD49_ZERO} from "./Constants.sol";

library PRBMathExtra {
    error SD49x28_IntoSD59x18_Overflow(SD59x18 x);
    error UD60x18_IntoUD50x28_Overflow(UD60x18 x);

    function intoSD49x28(SD59x18 x) internal pure returns (SD49x28 result) {
        int256 xUint = x.unwrap() * int256(1e10); // Scaling factor = 10 ** (28 - 18)
        if (xUint > uMAX_SD49x28) revert SD49x28_IntoSD59x18_Overflow(x);
        result = SD49x28.wrap(xUint);
    }

    function intoUD50x28(UD60x18 x) internal pure returns (UD50x28 result) {
        uint256 xUint = x.unwrap() * 1e10; // Scaling factor = 10 ** (28 - 18)
        if (xUint > uMAX_UD50x28) revert UD60x18_IntoUD50x28_Overflow(x);
        result = UD50x28.wrap(xUint);
    }

    //

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

    ////////////////////////

    /// @notice Returns the greater of two numbers `a` and `b`
    function max(UD50x28 a, UD50x28 b) internal pure returns (UD50x28) {
        return a > b ? a : b;
    }

    /// @notice Returns the lesser of two numbers `a` and `b`
    function min(UD50x28 a, UD50x28 b) internal pure returns (UD50x28) {
        return a > b ? b : a;
    }

    /// @notice Returns the greater of two numbers `a` and `b`
    function max(SD49x28 a, SD49x28 b) internal pure returns (SD49x28) {
        return a > b ? a : b;
    }

    /// @notice Returns the lesser of two numbers `a` and `b`
    function min(SD49x28 a, SD49x28 b) internal pure returns (SD49x28) {
        return a > b ? b : a;
    }

    /// @notice Returns the sum of `a` and `b`
    function add(UD50x28 a, SD49x28 b) internal pure returns (UD50x28) {
        return b < SD49_ZERO ? sub(a, -b) : a + b.intoUD50x28();
    }

    /// @notice Returns the difference of `a` and `b`
    function sub(UD50x28 a, SD49x28 b) internal pure returns (UD50x28) {
        return b < SD49_ZERO ? add(a, -b) : a - b.intoUD50x28();
    }
}
