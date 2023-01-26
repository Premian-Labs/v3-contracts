// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, add, ceil, div, exp, floor, ln, mul, pow, sqrt, sub, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

library OptionMath {

    // 59x18 fixed point integer constants
    SD59x18 internal constant ONE = SD59x18.wrap(1e18);
    SD59x18 internal constant TWO = SD59x18.wrap(2e18);
    SD59x18 internal constant ALPHA = SD59x18.wrap(-6.37309208e18);
    SD59x18 internal constant LAMBDA = SD59x18.wrap(-0.61228883e18);
    SD59x18 internal constant S1 = SD59x18.wrap(-0.11105481e18);
    SD59x18 internal constant S2 = SD59x18.wrap(0.44334159e18);
    SD59x18 internal constant LOG2 = ln(TWO);

    /**
     * @notice Helper function to evaluate used to compute the normal CDF approximation
     * @param x 59x18 fixed point representation of the input to the normal CDF
     * @return 59x18 fixed point representation of the value of the evaluated helper function
     */
    function _g(SD59x18 x) internal pure returns (SD59x18 result) {
        SD59x18 a = mul(div(ALPHA, LAMBDA), S1);
        SD59x18 b = pow(add(mul(S1, x), ONE), div(LAMBDA, S1));
        result = exp(mul(-LOG2, exp(add(mul(a, b), mul(S2, x)))));
    }
    /**
     * @notice Approximation of the normal CDF
     * @dev The approximation implemented is based on the paper
     * 'Accurate RMM-Based Approximations for the CDF of the Normal Distribution'
     * by Haim Shore
     * @param x input value to evaluate the normal CDF on, F(Z<=x)
     * @return SD59x18 fixed point representation of the normal CDF evaluated at x
     */
    function _normal_cdf(SD59x18 x) internal pure returns (SD59x18 result) {
        result = div(sub(add(ONE, _g(-x)), _g(x)), TWO);
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param spot59x18 59x18 fixed point representation of spot price
     * @param strike59x18 59x18 fixed point representation of strike price
     * @param timeToMaturity59x18 59x18 fixed point representation of duration of option contract (in years)
     * @param varAnnualized59x18 59x18 fixed point representation of annualized variance
     * @param isCall whether to price "call" or "put" option
     * @return 59x18 fixed point representation of Black-Scholes option price
     */
    function _blackScholesPrice(
        SD59x18 spot59x18,
        SD59x18 strike59x18,
        SD59x18 timeToMaturity59x18,
        SD59x18 varAnnualized59x18,
        bool isCall
    ) internal pure returns (SD59x18 price) {
        SD59x18 cumVar59x18 = mul(timeToMaturity59x18, varAnnualized59x18);
        SD59x18 cumVol59x18 = sqrt(cumVar59x18);

        SD59x18 d1_59x18 = div(add(ln(div(spot59x18, strike59x18)), div(cumVar59x18, TWO)), cumVol59x18);
        SD59x18 d2_59x18 = sub(d1_59x18, cumVol59x18);

        if (isCall) {
            SD59x18 a = mul(spot59x18, _normal_cdf(d1_59x18));
            SD59x18 b = mul(strike59x18, _normal_cdf(d2_59x18));
            price = sub(a, b);
        } else {
            SD59x18 a = mul(-spot59x18, _normal_cdf(-d1_59x18));
            SD59x18 b = mul(strike59x18, _normal_cdf(-d2_59x18));
            price = sub(a, b);
        }
    }
}
