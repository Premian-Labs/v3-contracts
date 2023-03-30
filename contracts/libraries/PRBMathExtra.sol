// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

library PRBMathExtra {
    SD59x18 private constant iZERO = SD59x18.wrap(0);

    /// @notice select the greater of two numbers
    /// @param a first number
    /// @param b second number
    /// @return greater number
    function max(UD60x18 a, UD60x18 b) internal pure returns (UD60x18) {
        return a > b ? a : b;
    }

    /// @notice select the lesser of two numbers
    /// @param a first number
    /// @param b second number
    /// @return lesser number
    function min(UD60x18 a, UD60x18 b) internal pure returns (UD60x18) {
        return a > b ? b : a;
    }

    /// @notice select the greater of two numbers
    /// @param a first number
    /// @param b second number
    /// @return greater number
    function max(SD59x18 a, SD59x18 b) internal pure returns (SD59x18) {
        return a > b ? a : b;
    }

    /// @notice select the lesser of two numbers
    /// @param a first number
    /// @param b second number
    /// @return lesser number
    function min(SD59x18 a, SD59x18 b) internal pure returns (SD59x18) {
        return a > b ? b : a;
    }

    function add(UD60x18 a, SD59x18 b) internal pure returns (UD60x18) {
        return b < iZERO ? sub(a, -b) : a + b.intoUD60x18();
    }

    function sub(UD60x18 a, SD59x18 b) internal pure returns (UD60x18) {
        return b < iZERO ? add(a, -b) : a - b.intoUD60x18();
    }
}
