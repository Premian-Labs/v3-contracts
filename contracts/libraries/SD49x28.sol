// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {mulDiv} from "@prb/math/Common.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

type SD49x28 is int256;

int256 constant uMAX_SD49x28 = 5789604461865809771178549250434395392663499233282_0282019728792003956564819967;
int256 constant uMIN_SD49x28 = -5789604461865809771178549250434395392663499233282_0282019728792003956564819968;

/// @dev The unit number, which gives the decimal precision of SD49x28.
int256 constant uUNIT = 1e28;
SD49x28 constant UNIT = SD49x28.wrap(uUNIT);

error SD49x28_IntoSD59x18_Overflow(SD59x18 x);
error SD49x28_Mul_InputTooSmall();
error SD49x28_Mul_Overflow(SD49x28 x, SD49x28 y);

error SD49x28_Div_InputTooSmall();
error SD49x28_Div_Overflow(SD49x28 x, SD49x28 y);

/// @notice Wraps a int256 number into the SD49x28 value type.
function wrap(int256 x) pure returns (SD49x28 result) {
    result = SD49x28.wrap(x);
}

/// @notice Unwraps a SD49x28 number into int256.
function unwrap(SD49x28 x) pure returns (int256 result) {
    result = SD49x28.unwrap(x);
}

function sd49x28(int256 x) pure returns (SD49x28 result) {
    result = SD49x28.wrap(x);
}

function intoSD49x28(SD59x18 x) pure returns (SD49x28 result) {
    int256 xUint = x.unwrap() * uUNIT;
    if (xUint > uMAX_SD49x28) revert SD49x28_IntoSD59x18_Overflow(x);
    result = wrap(xUint);
}

function intoSD59x18(SD49x28 x) pure returns (SD59x18 result) {
    result = SD59x18.wrap(x.unwrap() / uUNIT);
}

/// @notice Implements the checked addition operation (+) in the SD49x28 type.
function add(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    return wrap(x.unwrap() + y.unwrap());
}

/// @notice Implements the AND (&) bitwise operation in the SD49x28 type.
function and(SD49x28 x, int256 bits) pure returns (SD49x28 result) {
    return wrap(x.unwrap() & bits);
}

/// @notice Implements the AND (&) bitwise operation in the SD49x28 type.
function and2(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    return wrap(x.unwrap() & y.unwrap());
}

/// @notice Implements the equal (=) operation in the SD49x28 type.
function eq(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() == y.unwrap();
}

/// @notice Implements the greater than operation (>) in the SD49x28 type.
function gt(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() > y.unwrap();
}

/// @notice Implements the greater than or equal to operation (>=) in the SD49x28 type.
function gte(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() >= y.unwrap();
}

/// @notice Implements a zero comparison check function in the SD49x28 type.
function isZero(SD49x28 x) pure returns (bool result) {
    result = x.unwrap() == 0;
}

/// @notice Implements the left shift operation (<<) in the SD49x28 type.
function lshift(SD49x28 x, uint256 bits) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() << bits);
}

/// @notice Implements the lower than operation (<) in the SD49x28 type.
function lt(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() < y.unwrap();
}

/// @notice Implements the lower than or equal to operation (<=) in the SD49x28 type.
function lte(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() <= y.unwrap();
}

/// @notice Implements the unchecked modulo operation (%) in the SD49x28 type.
function mod(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() % y.unwrap());
}

/// @notice Implements the not equal operation (!=) in the SD49x28 type.
function neq(SD49x28 x, SD49x28 y) pure returns (bool result) {
    result = x.unwrap() != y.unwrap();
}

/// @notice Implements the NOT (~) bitwise operation in the SD49x28 type.
function not(SD49x28 x) pure returns (SD49x28 result) {
    result = wrap(~x.unwrap());
}

/// @notice Implements the OR (|) bitwise operation in the SD49x28 type.
function or(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() | y.unwrap());
}

/// @notice Implements the right shift operation (>>) in the SD49x28 type.
function rshift(SD49x28 x, uint256 bits) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() >> bits);
}

/// @notice Implements the checked subtraction operation (-) in the SD49x28 type.
function sub(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() - y.unwrap());
}

/// @notice Implements the checked unary minus operation (-) in the SD49x28 type.
function unary(SD49x28 x) pure returns (SD49x28 result) {
    result = wrap(-x.unwrap());
}

/// @notice Implements the unchecked addition operation (+) in the SD49x28 type.
function uncheckedAdd(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    unchecked {
        result = wrap(x.unwrap() + y.unwrap());
    }
}

/// @notice Implements the unchecked subtraction operation (-) in the SD49x28 type.
function uncheckedSub(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    unchecked {
        result = wrap(x.unwrap() - y.unwrap());
    }
}

/// @notice Implements the unchecked unary minus operation (-) in the SD49x28 type.
function uncheckedUnary(SD49x28 x) pure returns (SD49x28 result) {
    unchecked {
        result = wrap(-x.unwrap());
    }
}

/// @notice Implements the XOR (^) bitwise operation in the SD49x28 type.
function xor(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    result = wrap(x.unwrap() ^ y.unwrap());
}

/// @notice Calculates the arithmetic average of x and y.
///
/// @dev Notes:
/// - The result is rounded toward zero.
///
/// @param x The first operand as an SD49x28 number.
/// @param y The second operand as an SD49x28 number.
/// @return result The arithmetic average as an SD49x28 number.
/// @custom:smtchecker abstract-function-nondet
function avg(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    int256 xInt = x.unwrap();
    int256 yInt = y.unwrap();

    unchecked {
        // This operation is equivalent to `x / 2 +  y / 2`, and it can never overflow.
        int256 sum = (xInt >> 1) + (yInt >> 1);

        if (sum < 0) {
            // If at least one of x and y is odd, add 1 to the result, because shifting negative numbers to the right
            // rounds down to infinity. The right part is equivalent to `sum + (x % 2 == 1 || y % 2 == 1)`.
            assembly ("memory-safe") {
                result := add(sum, and(or(xInt, yInt), 1))
            }
        } else {
            // Add 1 if both x and y are odd to account for the double 0.5 remainder truncated after shifting.
            result = wrap(sum + (xInt & yInt & 1));
        }
    }
}

/// @notice Divides two SD49x28 numbers, returning a new SD49x28 number.
///
/// @dev This is an extension of {Common.mulDiv} for signed numbers, which works by computing the signs and the absolute
/// values separately.
///
/// Notes:
/// - Refer to the notes in {Common.mulDiv}.
/// - The result is rounded toward zero.
///
/// Requirements:
/// - Refer to the requirements in {Common.mulDiv}.
/// - None of the inputs can be `MIN_SD49x28`.
/// - The denominator must not be zero.
/// - The result must fit in SD49x28.
///
/// @param x The numerator as an SD49x28 number.
/// @param y The denominator as an SD49x28 number.
/// @param result The quotient as an SD49x28 number.
/// @custom:smtchecker abstract-function-nondet
function div(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    int256 xInt = x.unwrap();
    int256 yInt = y.unwrap();
    if (xInt == uMIN_SD49x28 || yInt == uMIN_SD49x28) {
        revert SD49x28_Div_InputTooSmall();
    }

    // Get hold of the absolute values of x and y.
    uint256 xAbs;
    uint256 yAbs;
    unchecked {
        xAbs = xInt < 0 ? uint256(-xInt) : uint256(xInt);
        yAbs = yInt < 0 ? uint256(-yInt) : uint256(yInt);
    }

    // Compute the absolute value (x*UNIT÷y). The resulting value must fit in SD49x28.
    uint256 resultAbs = mulDiv(xAbs, uint256(uUNIT), yAbs);
    if (resultAbs > uint256(uMAX_SD49x28)) {
        revert SD49x28_Div_Overflow(x, y);
    }

    // Check if x and y have the same sign using two's complement representation. The left-most bit represents the sign (1 for
    // negative, 0 for positive or zero).
    bool sameSign = (xInt ^ yInt) > -1;

    // If the inputs have the same sign, the result should be positive. Otherwise, it should be negative.
    unchecked {
        result = wrap(sameSign ? int256(resultAbs) : -int256(resultAbs));
    }
}

/// @notice Multiplies two SD49x28 numbers together, returning a new SD49x28 number.
///
/// @dev Notes:
/// - Refer to the notes in {Common.mulDiv18}.
///
/// Requirements:
/// - Refer to the requirements in {Common.mulDiv18}.
/// - None of the inputs can be `MIN_SD49x28`.
/// - The result must fit in SD49x28.
///
/// @param x The multiplicand as an SD49x28 number.
/// @param y The multiplier as an SD49x28 number.
/// @return result The product as an SD49x28 number.
/// @custom:smtchecker abstract-function-nondet
function mul(SD49x28 x, SD49x28 y) pure returns (SD49x28 result) {
    int256 xInt = x.unwrap();
    int256 yInt = y.unwrap();
    if (xInt == uMIN_SD49x28 || yInt == uMIN_SD49x28) {
        revert SD49x28_Mul_InputTooSmall();
    }

    // Get hold of the absolute values of x and y.
    uint256 xAbs;
    uint256 yAbs;
    unchecked {
        xAbs = xInt < 0 ? uint256(-xInt) : uint256(xInt);
        yAbs = yInt < 0 ? uint256(-yInt) : uint256(yInt);
    }

    // Compute the absolute value (x*y÷UNIT). The resulting value must fit in SD49x28.
    uint256 resultAbs = mulDiv(xAbs, yAbs, uint256(uUNIT));
    if (resultAbs > uint256(uMAX_SD49x28)) {
        revert SD49x28_Mul_Overflow(x, y);
    }

    // Check if x and y have the same sign using two's complement representation. The left-most bit represents the sign (1 for
    // negative, 0 for positive or zero).
    bool sameSign = (xInt ^ yInt) > -1;

    // If the inputs have the same sign, the result should be positive. Otherwise, it should be negative.
    unchecked {
        result = wrap(sameSign ? int256(resultAbs) : -int256(resultAbs));
    }
}

//////////////////////////////////////////////////////////////////////////

// The global "using for" directive makes the functions in this library callable on the SD49x28 type.
using {
    unwrap,
    intoSD59x18,
    avg,
    add,
    and,
    eq,
    gt,
    gte,
    isZero,
    lshift,
    lt,
    lte,
    mod,
    neq,
    not,
    or,
    rshift,
    sub,
    uncheckedAdd,
    uncheckedSub,
    xor
} for SD49x28 global;

// The global "using for" directive makes it possible to use these operators on the SD49x28 type.
using {
    add as +,
    and2 as &,
    div as /,
    eq as ==,
    gt as >,
    gte as >=,
    lt as <,
    lte as <=,
    or as |,
    mod as %,
    mul as *,
    neq as !=,
    not as ~,
    sub as -,
    xor as ^
} for SD49x28 global;
