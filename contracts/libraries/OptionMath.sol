// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, add, ceil, div, exp, floor, ln, mul, pow, sqrt, sub, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

library OptionMath {

    // 59x18 fixed point integer constants
    SD59x18 internal constant ONE = SD59x18.wrap(1e18);
    SD59x18 internal constant negONE = SD59x18.wrap(- 1e18);
    SD59x18 internal constant TWO = SD59x18.wrap(2e18);
    SD59x18 internal constant ALPHA = SD59x18.wrap(- 6.37309208e18);
    SD59x18 internal constant LAMBDA = SD59x18.wrap(- 0.61228883e18);
    SD59x18 internal constant S1 = SD59x18.wrap(- 0.11105481e18);
    SD59x18 internal constant S2 = SD59x18.wrap( 0.44334159e18);

    function _neg(SD59x18 x) internal pure returns (SD59x18 result) {
        return mul(x, negONE);
    }

    /**
     * @notice Helper function to evaluate used to compute the normal CDF approximation
     * @param x 59x18 fixed point representation of the input to the normal CDF
     * @return result 59x18 fixed point representation of the value of the evaluated helper function
     */
    function _helperNormal(SD59x18 x) internal pure returns (SD59x18 result) {
        SD59x18 a = ALPHA.div(LAMBDA).mul(S1);
        SD59x18 b = S1.mul(x).add(ONE).pow(LAMBDA.div(S1)).sub(ONE);
        result = a.mul(b).add(S2.mul(x)).exp().mul(_neg(ln(TWO))).exp();
    }

    /**
     * @notice Approximation of the normal CDF
     * @dev The approximation implemented is based on the paper
     * 'Accurate RMM-Based Approximations for the CDF of the Normal Distribution'
     * by Haim Shore
     * @param x input value to evaluate the normal CDF on, F(Z<=x)
     * @return result SD59x18 fixed point representation of the normal CDF evaluated at x
     */
    function _normalCdf(SD59x18 x) internal pure returns (SD59x18 result) {
        result = ONE.add(_helperNormal(_neg(x))).sub(_helperNormal(x)).div(TWO);
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @param spot59x18 59x18 fixed point representation of spot price
     * @param strike59x18 59x18 fixed point representation of strike price
     * @param timeToMaturity59x18 59x18 fixed point representation of duration of option contract (in years)
     * @param varAnnualized59x18 59x18 fixed point representation of annualized variance
     * @param isCall whether to price "call" or "put" option
     * @return price 59x18 fixed point representation of Black-Scholes option price
     */
    function _blackScholesPrice(
        SD59x18 spot59x18,
        SD59x18 strike59x18,
        SD59x18 timeToMaturity59x18,
        SD59x18 varAnnualized59x18,
        bool isCall
    ) internal pure returns (SD59x18 price) {
        SD59x18 cumVar59x18 = timeToMaturity59x18.mul(varAnnualized59x18);
        SD59x18 cumVol59x18 = cumVar59x18.sqrt();

        SD59x18 d1_59x18 = spot59x18.div(strike59x18).ln().add(cumVar59x18.div(TWO)).div(cumVol59x18);
        SD59x18 d2_59x18 = d1_59x18.sub(cumVol59x18);

        if (isCall) {
            SD59x18 a = spot59x18.mul(_normalCdf(_neg(d1_59x18)));
            SD59x18 b = strike59x18.mul(_normalCdf(d2_59x18));
            price = sub(a, b);
        } else {
            SD59x18 a = _neg(spot59x18).mul(_normalCdf(_neg(d1_59x18)));
            SD59x18 b = strike59x18.mul(_normalCdf(_neg(d2_59x18)));
            price = sub(a, b);
        }
    }
}
