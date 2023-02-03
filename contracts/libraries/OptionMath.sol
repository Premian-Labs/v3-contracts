// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, wrap, unwrap} from "@prb/math/src/SD59x18.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    // 59x18 fixed point integer constants
    SD59x18 internal constant ZERO = SD59x18.wrap(0e18);
    SD59x18 internal constant ONE = SD59x18.wrap(1e18);
    SD59x18 internal constant NEG_ONE = SD59x18.wrap(-1e18);
    SD59x18 internal constant TWO = SD59x18.wrap(2e18);
    SD59x18 internal constant ALPHA = SD59x18.wrap(-6.37309208e18);
    SD59x18 internal constant LAMBDA = SD59x18.wrap(-0.61228883e18);
    SD59x18 internal constant S1 = SD59x18.wrap(-0.11105481e18);
    SD59x18 internal constant S2 = SD59x18.wrap(0.44334159e18);

    function neg(SD59x18 x) internal pure returns (SD59x18 result) {
        return x.mul(NEG_ONE);
    }

    /// @notice Helper function to evaluate used to compute the normal CDF approximation
    /// @param x 59x18 fixed point representation of the input to the normal CDF
    /// @return result 59x18 fixed point representation of the value of the evaluated helper function
    function helperNormal(SD59x18 x) internal pure returns (SD59x18 result) {
        SD59x18 a = ALPHA.div(LAMBDA).mul(S1);
        SD59x18 b = S1.mul(x).add(ONE).pow(LAMBDA.div(S1)).sub(ONE);
        result = a.mul(b).add(S2.mul(x)).exp().mul(neg(TWO.ln())).exp();
    }

    /// @notice Approximation of the normal CDF
    /// @dev The approximation implemented is based on the paper
    /// 'Accurate RMM-Based Approximations for the CDF of the Normal Distribution'
    /// by Haim Shore
    /// @param x input value to evaluate the normal CDF on, F(Z<=x)
    /// @return result SD59x18 fixed point representation of the normal CDF evaluated at x
    function normalCdf(SD59x18 x) internal pure returns (SD59x18 result) {
        result = ONE.add(helperNormal(neg(x))).sub(helperNormal(x)).div(TWO);
    }

    /// @notice Implementation of the ReLu function f(x)=(x)^+ to compute call / put payoffs
    /// @param x SD59x18 input value to evaluate the
    /// @return result SD59x18 output of the relu function
    function relu(SD59x18 x) internal pure returns (SD59x18 result) {
        if (x.gte(ZERO)) {
            result = x;
        } else {
            result = ZERO;
        }
    }

    /// @notice Calculate the price of an option using the Black-Scholes model
    /// @dev this implementation assumes zero interest
    /// @param spot 59x18 fixed point representation of spot price
    /// @param strike 59x18 fixed point representation of strike price
    /// @param timeToMaturity 59x18 fixed point representation of duration of option contract (in years)
    /// @param volAnnualized 59x18 fixed point representation of annualized volatility
    /// @param riskFreeRate 59x18 fixed point representation the risk-free frate
    /// @param isCall whether to price "call" or "put" option
    /// @return price 59x18 fixed point representation of Black-Scholes option price
    function blackScholesPrice(
        SD59x18 spot,
        SD59x18 strike,
        SD59x18 timeToMaturity,
        SD59x18 volAnnualized,
        SD59x18 riskFreeRate,
        bool isCall
    ) internal pure returns (SD59x18 price) {
        if (timeToMaturity.eq(ZERO)) {
            if (isCall) {
                price = relu(spot.sub(strike));
            } else {
                price = relu(strike.sub(spot));
            }
            return price;
        }

        SD59x18 discountFactor = riskFreeRate.mul(timeToMaturity).exp();
        if (volAnnualized.eq(ZERO)) {
            if (isCall) {
                price = relu(spot.sub(strike.div(discountFactor)));
            } else {
                price = relu(strike.div(discountFactor).sub(spot));
            }
            return price;
        }

        SD59x18 timeScaledVol = timeToMaturity.mul(volAnnualized);
        SD59x18 timeScaledVar = timeScaledVol.pow(TWO);
        SD59x18 timeScaledRiskFreeRate = timeToMaturity.mul(riskFreeRate);

        SD59x18 d1 = spot
            .div(strike)
            .ln()
            .add(timeScaledVar.div(TWO))
            .add(timeScaledRiskFreeRate)
            .div(timeScaledVol);
        SD59x18 d2 = d1.sub(timeScaledVol);

        SD59x18 sign;
        if (isCall) {
            sign = ONE;
        } else {
            sign = NEG_ONE;
        }
        SD59x18 a = spot.mul(normalCdf(d1.mul(sign)));
        SD59x18 b = strike.div(discountFactor).mul(normalCdf(d2.mul(sign)));
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
    /// @param spot The spot price of the base asset
    /// @return The strike interval
    function calculateStrikeInterval(
        int256 spot
    ) internal pure returns (int256) {
        SD59x18 FIVE = wrap(5e18);
        SD59x18 TEN = wrap(10e18);

        SD59x18 SPOT = wrap(spot);

        SD59x18 o = SPOT.log10().floor();

        SD59x18 x = SPOT.mul(TEN.pow(o.mul(NEG_ONE).sub(ONE)));

        SD59x18 f = TEN.pow(o.sub(ONE));
        SD59x18 y = x.lt(wrap(0.5e18)) ? ONE.mul(f) : FIVE.mul(f);
        return unwrap(SPOT.lt(wrap(1000e18)) ? y : y.ceil());
    }
}
