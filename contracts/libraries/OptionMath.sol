// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, ceil, log10, mul, pow, sd} from "@prb/math/src/SD59x18.sol";

// TODO: Beta setter should check if newBeta is divisible by 0.25 and between 0.25 and 1

library OptionMath {
    function strikeInterval(
        SD59x18 beta,
        SD59x18 spot
    ) internal pure returns (SD59x18) {
        SD59x18 ALPHA_59X18 = sd(2e18);
        SD59x18 TEN_59X18 = sd(10e18);

        // x = ceil(log10(spot)) + alpha
        // y = beta * 10^x
        // where alpha = -2, beta = [0.25, 0.5, 0.75, 1]

        SD59x18 x = ceil(log10(spot)).sub(ALPHA_59X18);
        SD59x18 y = beta.mul(TEN_59X18.pow(x));

        if (spot.gt(sd(1000e18))) {
            // spot > 1000E18, strike interval will always have a small rounding error
            return ceil(y);
        }

        return y;
    }
}
