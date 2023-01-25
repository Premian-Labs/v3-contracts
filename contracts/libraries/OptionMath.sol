// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, ceil, floor, log10, mul, pow, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

library OptionMath {

    // 64x64 fixed point integer constants
    int128 internal constant ONE = 1e18;
    int128 internal constant THREE = 3e18;

    // 64x64 fixed point constants used in Choudhury’s approximation of the Normal CDF
    int128 private constant CDF_CONST_0 = 0x09109f285df452394; // 2260 / 3989
    int128 private constant CDF_CONST_1 = 0x19abac0ea1da65036; // 6400 / 3989
    int128 private constant CDF_CONST_2 = 0x0d3c84b78b749bd6b; // 3300 / 3989

    /**
     * @notice calculate Choudhury’s approximation of the Black-Scholes CDF
     * @param input64x64 64x64 fixed point representation of random variable
     * @return 64x64 fixed point representation of the approximated CDF of x
     */
    function _N(int128 input64x64) internal pure returns (int128) {
        // squaring via mul is cheaper than via pow
        int128 inputSquared64x64 = input64x64.mul(input64x64);

        int128 value64x64 = (-inputSquared64x64 >> 1).exp().div(
            CDF_CONST_0.add(CDF_CONST_1.mul(input64x64.abs())).add(
                CDF_CONST_2.mul(inputSquared64x64.add(THREE_64x64).sqrt())
            )
        );

        return input64x64 > 0 ? ONE_64x64.sub(value64x64) : value64x64;
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param varianceAnnualized64x64 64x64 fixed point representation of annualized variance
     * @param strike64x64 64x64 fixed point representation of strike price
     * @param spot64x64 64x64 fixed point representation of spot price
     * @param timeToMaturity64x64 64x64 fixed point representation of duration of option contract (in years)
     * @param isCall whether to price "call" or "put" option
     * @return 64x64 fixed point representation of Black-Scholes option price
     */
    function _blackScholesPrice(
        int128 varianceAnnualized64x64,
        int128 strike64x64,
        int128 spot64x64,
        int128 timeToMaturity64x64,
        bool isCall
    ) internal pure returns (int128) {
        int128 cumulativeVariance64x64 = timeToMaturity64x64.mul(
            varianceAnnualized64x64
        );
        int128 cumulativeVarianceSqrt64x64 = cumulativeVariance64x64.sqrt();

        int128 d1_64x64 = spot64x64
        .div(strike64x64)
        .ln()
        .add(cumulativeVariance64x64 >> 1)
        .div(cumulativeVarianceSqrt64x64);
        int128 d2_64x64 = d1_64x64.sub(cumulativeVarianceSqrt64x64);

        if (isCall) {
            return
            spot64x64.mul(_N(d1_64x64)).sub(strike64x64.mul(_N(d2_64x64)));
        } else {
            return
            -spot64x64.mul(_N(-d1_64x64)).sub(
                strike64x64.mul(_N(-d2_64x64))
            );
        }
    }
}
