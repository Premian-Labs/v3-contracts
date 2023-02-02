// SPDX-License-Identifier: MIT
// https://github.com/PaulRBerg/prb-math
pragma solidity >=0.8.13;

import {msb, mulDiv, mulDiv18, prbExp2, prbSqrt} from "./Core.sol";

library UD60x18 {
    /// @notice Emitted when adding two numbers overflows UD60x18.
    error PRBMathUD60x18__AddOverflow(uint256 x, uint256 y);

    /// @notice Emitted when ceiling a number overflows UD60x18.
    error PRBMathUD60x18__CeilOverflow(uint256 x);

    /// @notice Emitted when taking the natural exponent of a base greater than 133.084258667509499441.
    error PRBMathUD60x18__ExpInputTooBig(uint256 x);

    /// @notice Emitted when taking the binary exponent of a base greater than 192.
    error PRBMathUD60x18__Exp2InputTooBig(uint256 x);

    /// @notice Emitted when taking the geometric mean of two numbers and multiplying them overflows UD60x18.
    error PRBMathUD60x18__GmOverflow(uint256 x, uint256 y);

    /// @notice Emitted when taking the logarithm of a number less than 1.
    error PRBMathUD60x18__LogInputTooSmall(uint256 x);

    /// @notice Emitted when calculating the square root overflows UD60x18.
    error PRBMathUD60x18__SqrtOverflow(uint256 x);

    /// @notice Emitted when subtracting one number from another underflows UD60x18.
    error PRBMathUD60x18__SubUnderflow(uint256 x, uint256 y);

    /// @notice Emitted when converting a basic integer to the fixed-point format overflows UD60x18.
    error PRBMathUD60x18__ToUD60x18Overflow(uint256 x);

    //////////////////
    //////////////////
    //////////////////

    /// @dev Half the UNIT number.
    uint256 constant HALF_UNIT = 0.5e18;

    /// @dev log2(10) as an UD60x18 number.
    uint256 constant LOG2_10 = 3_321928094887362347;

    /// @dev log2(e) as an UD60x18 number.
    uint256 constant LOG2_E = 1_442695040888963407;

    /// @dev The maximum value an UD60x18 number can have.
    uint256 constant MAX_UD60x18 =
        115792089237316195423570985008687907853269984665640564039457_584007913129639935;

    /// @dev The maximum whole value an UD60x18 number can have.
    uint256 constant MAX_WHOLE_UD60x18 =
        115792089237316195423570985008687907853269984665640564039457_000000000000000000;

    /// @dev The unit amount which implies how many trailing decimals can be represented.
    uint256 constant UNIT = 1e18;

    //////////////////
    //////////////////
    //////////////////

    /// @notice Calculates the arithmetic average of x and y, rounding down.
    ///
    /// @dev Based on the formula:
    ///
    /// $$
    /// avg(x, y) = (x & y) + ((xUint ^ yUint) / 2)
    /// $$
    //
    /// In English, what this formula does is:
    ///
    /// 1. AND x and y.
    /// 2. Calculate half of XOR x and y.
    /// 3. Add the two results together.
    ///
    /// This technique is known as SWAR, which stands for "SIMD within a register". You can read more about it here:
    /// https://devblogs.microsoft.com/oldnewthing/20220207-00/?p=106223
    ///
    /// @param x The first operand as an UD60x18 number.
    /// @param y The second operand as an UD60x18 number.
    /// @return result The arithmetic average as an UD60x18 number.
    function avg(uint256 x, uint256 y) internal pure returns (uint256 result) {
        unchecked {
            result = (x & y) + ((x ^ y) >> 1);
        }
    }

    /// @notice Yields the smallest whole UD60x18 number greater than or equal to x.
    ///
    /// @dev This is optimized for fractional value inputs, because for every whole value there are "1e18 - 1" fractional
    /// counterparts. See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
    ///
    /// Requirements:
    /// - x must be less than or equal to `MAX_WHOLE_UD60x18`.
    ///
    /// @param x The UD60x18 number to ceil.
    /// @param result The least number greater than or equal to x, as an UD60x18 number.
    function ceil(uint256 x) internal pure returns (uint256 result) {
        if (x > MAX_WHOLE_UD60x18) {
            revert PRBMathUD60x18__CeilOverflow(x);
        }

        assembly {
            // Equivalent to "x % UNIT" but faster.
            let remainder := mod(x, UNIT)

            // Equivalent to "UNIT - remainder" but faster.
            let delta := sub(UNIT, remainder)

            // Equivalent to "x + delta * (remainder > 0 ? 1 : 0)" but faster.
            result := add(x, mul(delta, gt(remainder, 0)))
        }
    }

    /// @notice Divides two UD60x18 numbers, returning a new UD60x18 number. Rounds towards zero.
    ///
    /// @dev Uses `mulDiv` to enable overflow-safe multiplication and division.
    ///
    /// Requirements:
    /// - The denominator cannot be zero.
    ///
    /// @param x The numerator as an UD60x18 number.
    /// @param y The denominator as an UD60x18 number.
    /// @param result The quotient as an UD60x18 number.
    function div(uint256 x, uint256 y) internal pure returns (uint256 result) {
        result = mulDiv(x, UNIT, y);
    }

    /// @notice Calculates the natural exponent of x.
    ///
    /// @dev Based on the formula:
    ///
    /// $$
    /// e^x = 2^{x * log_2{e}}
    /// $$
    ///
    /// Requirements:
    /// - All from `log2`.
    /// - x must be less than 133.084258667509499441.
    ///
    /// @param x The exponent as an UD60x18 number.
    /// @return result The result as an UD60x18 number.
    function exp(uint256 x) internal pure returns (uint256 result) {
        // Without this check, the value passed to `exp2` would be greater than 192.
        if (x >= 133_084258667509499441) {
            revert PRBMathUD60x18__ExpInputTooBig(x);
        }

        unchecked {
            // We do the fixed-point multiplication inline rather than via the `mul` function to save gas.
            uint256 doubleUnitProduct = x * LOG2_E;
            result = exp2(doubleUnitProduct / UNIT);
        }
    }

    /// @notice Calculates the binary exponent of x using the binary fraction method.
    ///
    /// @dev See https://ethereum.stackexchange.com/q/79903/24693.
    ///
    /// Requirements:
    /// - x must be 192 or less.
    /// - The result must fit within `MAX_UD60x18`.
    ///
    /// @param x The exponent as an UD60x18 number.
    /// @return result The result as an UD60x18 number.
    function exp2(uint256 x) internal pure returns (uint256 result) {
        // Numbers greater than or equal to 2^192 don't fit within the 192.64-bit format.
        if (x >= 192e18) {
            revert PRBMathUD60x18__Exp2InputTooBig(x);
        }

        // Convert x to the 192.64-bit fixed-point format.
        uint256 x_192x64 = (x << 64) / UNIT;

        // Pass x to the `prbExp2` function, which uses the 192.64-bit fixed-point number representation.
        result = prbExp2(x_192x64);
    }

    /// @notice Yields the greatest whole UD60x18 number less than or equal to x.
    /// @dev Optimized for fractional value inputs, because for every whole value there are (1e18 - 1) fractional counterparts.
    /// See https://en.wikipedia.org/wiki/Floor_and_ceiling_functions.
    /// @param x The UD60x18 number to floor.
    /// @param result The greatest integer less than or equal to x, as an UD60x18 number.
    function floor(uint256 x) internal pure returns (uint256 result) {
        assembly {
            // Equivalent to "x % UNIT" but faster.
            let remainder := mod(x, UNIT)

            // Equivalent to "x - remainder * (remainder > 0 ? 1 : 0)" but faster.
            result := sub(x, mul(remainder, gt(remainder, 0)))
        }
    }

    /// @notice Yields the excess beyond the floor of x.
    /// @dev Based on the odd function definition https://en.wikipedia.org/wiki/Fractional_part.
    /// @param x The UD60x18 number to get the fractional part of.
    /// @param result The fractional part of x as an UD60x18 number.
    function frac(uint256 x) internal pure returns (uint256 result) {
        assembly {
            result := mod(x, UNIT)
        }
    }

    /// @notice Calculates the geometric mean of x and y, i.e. $$sqrt(x * y)$$, rounding down.
    ///
    /// @dev Requirements:
    /// - x * y must fit within `MAX_UD60x18`, lest it overflows.
    ///
    /// @param x The first operand as an UD60x18 number.
    /// @param y The second operand as an UD60x18 number.
    /// @return result The result as an UD60x18 number.
    function gm(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (x == 0 || y == 0) {
            return 0;
        }

        unchecked {
            // Checking for overflow this way is faster than letting Solidity do it.
            uint256 xy = x * y;
            if (xy / x != y) {
                revert PRBMathUD60x18__GmOverflow(x, y);
            }

            // We don't need to multiply the result by `UNIT` here because the x*y product had picked up a factor of `UNIT`
            // during multiplication. See the comments in the `prbSqrt` function.
            result = prbSqrt(xy);
        }
    }

    /// @notice Calculates 1 / x, rounding toward zero.
    ///
    /// @dev Requirements:
    /// - x cannot be zero.
    ///
    /// @param x The UD60x18 number for which to calculate the inverse.
    /// @return result The inverse as an UD60x18 number.
    function inv(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            // 1e36 is UNIT * UNIT.
            result = 1e36 / x;
        }
    }

    /// @notice Calculates the natural logarithm of x.
    ///
    /// @dev Based on the formula:
    ///
    /// $$
    /// ln{x} = log_2{x} / log_2{e}$$.
    /// $$
    ///
    /// Requirements:
    /// - All from `log2`.
    ///
    /// Caveats:
    /// - All from `log2`.
    /// - This doesn't return exactly 1 for 2.718281828459045235, for that more fine-grained precision is needed.
    ///
    /// @param x The UD60x18 number for which to calculate the natural logarithm.
    /// @return result The natural logarithm as an UD60x18 number.
    function ln(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            // We do the fixed-point multiplication inline to save gas. This is overflow-safe because the maximum value
            // that `log2` can return is 196.205294292027477728.
            result = (log2(x) * UNIT) / LOG2_E;
        }
    }

    /// @notice Calculates the common logarithm of x.
    ///
    /// @dev First checks if x is an exact power of ten and it stops if yes. If it's not, calculates the common
    /// logarithm based on the formula:
    ///
    /// $$
    /// log_{10}{x} = log_2{x} / log_2{10}
    /// $$
    ///
    /// Requirements:
    /// - All from `log2`.
    ///
    /// Caveats:
    /// - All from `log2`.
    ///
    /// @param x The UD60x18 number for which to calculate the common logarithm.
    /// @return result The common logarithm as an UD60x18 number.
    function log10(uint256 x) internal pure returns (uint256 result) {
        if (x < UNIT) {
            revert PRBMathUD60x18__LogInputTooSmall(x);
        }

        // Note that the `mul` in this assembly block is the assembly multiplication operation, not the UD60x18 `mul`.
        // prettier-ignore
        assembly {
        switch x
        case 1 { result := mul(UNIT, sub(0, 18)) }
        case 10 { result := mul(UNIT, sub(1, 18)) }
        case 100 { result := mul(UNIT, sub(2, 18)) }
        case 1000 { result := mul(UNIT, sub(3, 18)) }
        case 10000 { result := mul(UNIT, sub(4, 18)) }
        case 100000 { result := mul(UNIT, sub(5, 18)) }
        case 1000000 { result := mul(UNIT, sub(6, 18)) }
        case 10000000 { result := mul(UNIT, sub(7, 18)) }
        case 100000000 { result := mul(UNIT, sub(8, 18)) }
        case 1000000000 { result := mul(UNIT, sub(9, 18)) }
        case 10000000000 { result := mul(UNIT, sub(10, 18)) }
        case 100000000000 { result := mul(UNIT, sub(11, 18)) }
        case 1000000000000 { result := mul(UNIT, sub(12, 18)) }
        case 10000000000000 { result := mul(UNIT, sub(13, 18)) }
        case 100000000000000 { result := mul(UNIT, sub(14, 18)) }
        case 1000000000000000 { result := mul(UNIT, sub(15, 18)) }
        case 10000000000000000 { result := mul(UNIT, sub(16, 18)) }
        case 100000000000000000 { result := mul(UNIT, sub(17, 18)) }
        case 1000000000000000000 { result := 0 }
        case 10000000000000000000 { result := UNIT }
        case 100000000000000000000 { result := mul(UNIT, 2) }
        case 1000000000000000000000 { result := mul(UNIT, 3) }
        case 10000000000000000000000 { result := mul(UNIT, 4) }
        case 100000000000000000000000 { result := mul(UNIT, 5) }
        case 1000000000000000000000000 { result := mul(UNIT, 6) }
        case 10000000000000000000000000 { result := mul(UNIT, 7) }
        case 100000000000000000000000000 { result := mul(UNIT, 8) }
        case 1000000000000000000000000000 { result := mul(UNIT, 9) }
        case 10000000000000000000000000000 { result := mul(UNIT, 10) }
        case 100000000000000000000000000000 { result := mul(UNIT, 11) }
        case 1000000000000000000000000000000 { result := mul(UNIT, 12) }
        case 10000000000000000000000000000000 { result := mul(UNIT, 13) }
        case 100000000000000000000000000000000 { result := mul(UNIT, 14) }
        case 1000000000000000000000000000000000 { result := mul(UNIT, 15) }
        case 10000000000000000000000000000000000 { result := mul(UNIT, 16) }
        case 100000000000000000000000000000000000 { result := mul(UNIT, 17) }
        case 1000000000000000000000000000000000000 { result := mul(UNIT, 18) }
        case 10000000000000000000000000000000000000 { result := mul(UNIT, 19) }
        case 100000000000000000000000000000000000000 { result := mul(UNIT, 20) }
        case 1000000000000000000000000000000000000000 { result := mul(UNIT, 21) }
        case 10000000000000000000000000000000000000000 { result := mul(UNIT, 22) }
        case 100000000000000000000000000000000000000000 { result := mul(UNIT, 23) }
        case 1000000000000000000000000000000000000000000 { result := mul(UNIT, 24) }
        case 10000000000000000000000000000000000000000000 { result := mul(UNIT, 25) }
        case 100000000000000000000000000000000000000000000 { result := mul(UNIT, 26) }
        case 1000000000000000000000000000000000000000000000 { result := mul(UNIT, 27) }
        case 10000000000000000000000000000000000000000000000 { result := mul(UNIT, 28) }
        case 100000000000000000000000000000000000000000000000 { result := mul(UNIT, 29) }
        case 1000000000000000000000000000000000000000000000000 { result := mul(UNIT, 30) }
        case 10000000000000000000000000000000000000000000000000 { result := mul(UNIT, 31) }
        case 100000000000000000000000000000000000000000000000000 { result := mul(UNIT, 32) }
        case 1000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 33) }
        case 10000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 34) }
        case 100000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 35) }
        case 1000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 36) }
        case 10000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 37) }
        case 100000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 38) }
        case 1000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 39) }
        case 10000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 40) }
        case 100000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 41) }
        case 1000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 42) }
        case 10000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 43) }
        case 100000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 44) }
        case 1000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 45) }
        case 10000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 46) }
        case 100000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 47) }
        case 1000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 48) }
        case 10000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 49) }
        case 100000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 50) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 51) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 52) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 53) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 54) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 55) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 56) }
        case 1000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 57) }
        case 10000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 58) }
        case 100000000000000000000000000000000000000000000000000000000000000000000000000000 { result := mul(UNIT, 59) }
        default {
            result := MAX_UD60x18
        }
    }

        if (result == MAX_UD60x18) {
            unchecked {
                // Do the fixed-point division inline to save gas.
                result = (log2(x) * UNIT) / LOG2_10;
            }
        }
    }

    /// @notice Calculates the binary logarithm of x.
    ///
    /// @dev Based on the iterative approximation algorithm.
    /// https://en.wikipedia.org/wiki/Binary_logarithm#Iterative_approximation
    ///
    /// Requirements:
    /// - x must be greater than or equal to UNIT, otherwise the result would be negative.
    ///
    /// Caveats:
    /// - The results are nor perfectly accurate to the last decimal, due to the lossy precision of the iterative approximation.
    ///
    /// @param x The UD60x18 number for which to calculate the binary logarithm.
    /// @return result The binary logarithm as an UD60x18 number.
    function log2(uint256 x) internal pure returns (uint256 result) {
        if (x < UNIT) {
            revert PRBMathUD60x18__LogInputTooSmall(x);
        }

        unchecked {
            // Calculate the integer part of the logarithm, add it to the result and finally calculate y = x * 2^(-n).
            uint256 n = msb(x / UNIT);

            // This is the integer part of the logarithm as an UD60x18 number. The operation can't overflow because n
            // n is maximum 255 and UNIT is 1e18.
            uint256 resultUint = n * UNIT;

            // This is $y = x * 2^{-n}$.
            uint256 y = x >> n;

            // If y is 1, the fractional part is zero.
            if (y == UNIT) {
                return resultUint;
            }

            // Calculate the fractional part via the iterative approximation.
            // The "delta.rshift(1)" part is equivalent to "delta /= 2", but shifting bits is faster.
            uint256 DOUBLE_UNIT = 2e18;
            for (uint256 delta = HALF_UNIT; delta > 0; delta >>= 1) {
                y = (y * y) / UNIT;

                // Is y^2 > 2 and so in the range [2,4)?
                if (y >= DOUBLE_UNIT) {
                    // Add the 2^{-m} factor to the logarithm.
                    resultUint += delta;

                    // Corresponds to z/2 on Wikipedia.
                    y >>= 1;
                }
            }
            result = resultUint;
        }
    }

    /// @notice Multiplies two UD60x18 numbers together, returning a new UD60x18 number.
    /// @dev See the documentation for the `Core/mulDiv18` function.
    /// @param x The multiplicand as an UD60x18 number.
    /// @param y The multiplier as an UD60x18 number.
    /// @return result The product as an UD60x18 number.
    function mul(uint256 x, uint256 y) internal pure returns (uint256 result) {
        result = mulDiv18(x, y);
    }

    /// @notice Raises x to the power of y.
    ///
    /// @dev Based on the formula:
    ///
    /// $$
    /// x^y = 2^{log_2{x} * y}
    /// $$
    ///
    /// Requirements:
    /// - All from `exp2`, `log2` and `mul`.
    ///
    /// Caveats:
    /// - All from `exp2`, `log2` and `mul`.
    /// - Assumes 0^0 is 1.
    ///
    /// @param x Number to raise to given power y, as an UD60x18 number.
    /// @param y Exponent to raise x to, as an UD60x18 number.
    /// @return result x raised to power y, as an UD60x18 number.
    function pow(uint256 x, uint256 y) internal pure returns (uint256 result) {
        if (x == 0) {
            result = y == 0 ? UNIT : 0;
        } else {
            if (y == UNIT) {
                result = x;
            } else {
                result = exp2(mul(log2(x), y));
            }
        }
    }

    /// @notice Raises x (an UD60x18 number) to the power y (unsigned basic integer) using the famous algorithm
    /// "exponentiation by squaring".
    ///
    /// @dev See https://en.wikipedia.org/wiki/Exponentiation_by_squaring
    ///
    /// Requirements:
    /// - The result must fit within `MAX_UD60x18`.
    ///
    /// Caveats:
    /// - All from "Core/mulDiv18".
    /// - Assumes 0^0 is 1.
    ///
    /// @param x The base as an UD60x18 number.
    /// @param y The exponent as an uint256.
    /// @return result The result as an UD60x18 number.
    function powu(uint256 x, uint256 y) internal pure returns (uint256 result) {
        // Calculate the first iteration of the loop in advance.
        uint256 resultUint = y & 1 > 0 ? x : UNIT;

        // Equivalent to "for(y /= 2; y > 0; y /= 2)" but faster.
        for (y >>= 1; y > 0; y >>= 1) {
            x = mulDiv18(x, x);

            // Equivalent to "y % 2 == 1" but faster.
            if (y & 1 > 0) {
                resultUint = mulDiv18(resultUint, x);
            }
        }
        result = resultUint;
    }

    /// @notice Calculates the square root of x, rounding down.
    /// @dev Uses the Babylonian method https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method.
    ///
    /// Requirements:
    /// - x must be less than `MAX_UD60x18` divided by `UNIT`.
    ///
    /// @param x The UD60x18 number for which to calculate the square root.
    /// @return result The result as an UD60x18 number.
    function sqrt(uint256 x) internal pure returns (uint256 result) {
        unchecked {
            if (x > MAX_UD60x18 / UNIT) {
                revert PRBMathUD60x18__SqrtOverflow(x);
            }
            // Multiply x by `UNIT` to account for the factor of `UNIT` that is picked up when multiplying two UD60x18
            // numbers together (in this case, the two numbers are both the square root).
            result = prbSqrt(x * UNIT);
        }
    }
}
