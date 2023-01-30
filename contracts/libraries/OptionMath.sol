// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, add, ceil, div, exp, floor, ln, mul, pow, sqrt, sub, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    // 59x18 fixed point integer constants
    SD59x18 internal constant ZERO = SD59x18.wrap(0e18);
    SD59x18 internal constant ONE = SD59x18.wrap(1e18);
    SD59x18 internal constant negONE = SD59x18.wrap(-1e18);
    SD59x18 internal constant TWO = SD59x18.wrap(2e18);
    SD59x18 internal constant ALPHA = SD59x18.wrap(-6.37309208e18);
    SD59x18 internal constant LAMBDA = SD59x18.wrap(-0.61228883e18);
    SD59x18 internal constant S1 = SD59x18.wrap(-0.11105481e18);
    SD59x18 internal constant S2 = SD59x18.wrap(0.44334159e18);

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

    function _relu(SD59x18 x) internal pure returns (SD59x18 result) {
        if (x.gte(ZERO)) {
            result = x;
        } else {
            result = ZERO;
        }
    }

    /**
     * @notice calculate the price of an option using the Black-Scholes model
     * @dev this implementation assumes zero interest
     * @param spot59x18 59x18 fixed point representation of spot price
     * @param strike59x18 59x18 fixed point representation of strike price
     * @param timeToMaturity59x18 59x18 fixed point representation of duration of option contract (in years)
     * @param volAnnualized59x18 59x18 fixed point representation of annualized volatility
     * @param riskFreeRate59x18 59x18 fixed point representation the risk-free frate
     * @param isCall whether to price "call" or "put" option
     * @return price 59x18 fixed point representation of Black-Scholes option price
     */
    function _blackScholesPrice(
        SD59x18 spot59x18,
        SD59x18 strike59x18,
        SD59x18 timeToMaturity59x18,
        SD59x18 volAnnualized59x18,
        SD59x18 riskFreeRate59x18,
        bool isCall
    ) internal pure returns (SD59x18 price) {
        if (timeToMaturity59x18.eq(ZERO)) {
            if (isCall) {
                price = _relu(spot59x18.sub(strike59x18));
            } else {
                price = _relu(strike59x18.sub(spot59x18));
            }
            return price;
        }

        SD59x18 discountFactor59x18 = riskFreeRate59x18
            .mul(timeToMaturity59x18)
            .exp();
        if (volAnnualized59x18.eq(ZERO)) {
            if (isCall) {
                price = _relu(
                    spot59x18.sub(strike59x18.div(discountFactor59x18))
                );
            } else {
                price = _relu(
                    strike59x18.div(discountFactor59x18).sub(spot59x18)
                );
            }
            return price;
        }

        SD59x18 timeScaledVol59x18 = timeToMaturity59x18.mul(
            volAnnualized59x18
        );
        SD59x18 timeScaledVar59x18 = timeScaledVol59x18.pow(TWO);
        SD59x18 timeScaledRiskFreeRate59x18 = timeToMaturity59x18.mul(
            riskFreeRate59x18
        );

        SD59x18 d1_59x18 = spot59x18
            .div(strike59x18)
            .ln()
            .add(timeScaledVar59x18.div(TWO))
            .add(timeScaledRiskFreeRate59x18)
            .div(timeScaledVol59x18);
        SD59x18 d2_59x18 = d1_59x18.sub(timeScaledVol59x18);

        SD59x18 sign;
        if (isCall) {
            sign = ONE;
        } else {
            sign = negONE;
        }
        SD59x18 a = spot59x18.mul(_normalCdf(d1_59x18.mul(sign)));
        SD59x18 b = strike59x18.div(discountFactor59x18).mul(
            _normalCdf(d2_59x18.mul(sign))
        );
        price = a.sub(b).mul(sign);
        return price;
    }

    /// @notice Returns true if the maturity day is Friday
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is Friday, false otherwise
    function isFriday(uint64 maturity) internal pure returns (bool) {
        return DateTime.getDayOfWeek(maturity) == DateTime.DOW_FRI;
    }

    /// @notice Returns true if the maturity day is the last Friday of the month
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is the last Friday of the month, false otherwise
    function isLastFriday(uint64 maturity) internal pure returns (bool) {
        uint256 dayOfMonth = DateTime.getDay(maturity);
        uint256 lastDayOfMonth = DateTime.getDaysInMonth(maturity);

        if (lastDayOfMonth - dayOfMonth > 7) return false;
        return isFriday(maturity);
    }

    /// @notice Calculates the time to maturity in seconds
    /// @param maturity The maturity timestamp of the option
    /// @return Time to maturity in seconds
    function calculateTimeToMaturity(
        uint64 maturity
    ) internal view returns (uint256) {
        return maturity - block.timestamp;
    }

    /// @notice Calculates the strike interval for the given spot price
    /// @param spot The spot price of the underlying asset
    /// @return The strike interval
    function calculateStrikeInterval(
        int256 spot
    ) internal pure returns (int256) {
        SD59x18 NEG_ONE_59X18 = wrap(-1e18);
        SD59x18 ONE_59X18 = wrap(1e18);

        SD59x18 FIVE_59X18 = wrap(5e18);
        SD59x18 TEN_59X18 = wrap(10e18);

        SD59x18 SPOT_59X18 = wrap(spot);

        SD59x18 o = SPOT_59X18.log10().floor();

        SD59x18 x = SPOT_59X18.mul(
            TEN_59X18.pow(o.mul(NEG_ONE_59X18).sub(ONE_59X18))
        );

        SD59x18 f = TEN_59X18.pow(o.sub(ONE_59X18));
        SD59x18 y = x.lt(wrap(0.5e18)) ? ONE_59X18.mul(f) : FIVE_59X18.mul(f);
        return unwrap(SPOT_59X18.lt(wrap(1000e18)) ? y : y.ceil());
    }
}
