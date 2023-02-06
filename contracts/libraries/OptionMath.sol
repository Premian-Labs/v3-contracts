// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18} from "./prbMath/SD59x18.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    using SD59x18 for int256;

    // To prevent stack too deep
    struct BlackScholesPriceInternal {
        int256 discountFactor;
        int256 timeScaledVol;
        int256 timeScaledVar;
        int256 timeScaledRiskFreeRate;
    }

    int256 internal constant ONE = 1e18;
    int256 internal constant TWO = 2e18;
    int256 internal constant ALPHA = -6.37309208e18;
    int256 internal constant LAMBDA = -0.61228883e18;
    int256 internal constant S1 = -0.11105481e18;
    int256 internal constant S2 = 0.44334159e18;

    /// @notice Helper function to evaluate used to compute the normal CDF approximation
    /// @param x 59x18 fixed point representation of the input to the normal CDF
    /// @return result 59x18 fixed point representation of the value of the evaluated helper function
    function helperNormal(int256 x) internal pure returns (int256 result) {
        int256 a = ALPHA.div(LAMBDA).mul(S1);
        int256 b = (S1.mul(x) + ONE).pow(LAMBDA.div(S1)) - ONE;
        result = (a.mul(b) + S2.mul(x)).exp().mul(-(TWO.ln())).exp();
    }

    /// @notice Approximation of the normal CDF
    /// @dev The approximation implemented is based on the paper
    /// 'Accurate RMM-Based Approximations for the CDF of the Normal Distribution'
    /// by Haim Shore
    /// @param x input value to evaluate the normal CDF on, F(Z<=x)
    /// @return result SD59x18 fixed point representation of the normal CDF evaluated at x
    function normalCdf(int256 x) internal pure returns (int256 result) {
        result = ((ONE + helperNormal(-x)) - helperNormal(x)).div(TWO);
    }

    /// @notice Implementation of the ReLu function f(x)=(x)^+ to compute call / put payoffs
    /// @param x SD59x18 input value to evaluate the
    /// @return result SD59x18 output of the relu function
    function relu(int256 x) internal pure returns (int256 result) {
        if (x >= 0) {
            result = x;
        } else {
            result = 0;
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
        int256 spot,
        int256 strike,
        int256 timeToMaturity,
        int256 volAnnualized,
        int256 riskFreeRate,
        bool isCall
    ) internal pure returns (int256 price) {
        if (timeToMaturity == 0) {
            if (isCall) {
                price = relu(spot - strike);
            } else {
                price = relu(strike - spot);
            }
            return price;
        }

        BlackScholesPriceInternal memory x;

        x.discountFactor = riskFreeRate.mul(timeToMaturity).exp();
        if (volAnnualized == 0) {
            if (isCall) {
                price = relu(spot - strike.div(x.discountFactor));
            } else {
                price = relu(strike.div(x.discountFactor) - spot);
            }
            return price;
        }

        x.timeScaledVol = timeToMaturity.mul(volAnnualized);
        x.timeScaledVar = x.timeScaledVol.pow(TWO);
        x.timeScaledRiskFreeRate = timeToMaturity.mul(riskFreeRate);

        int256 d1 = (spot.div(strike).ln() +
            x.timeScaledVar.div(TWO) +
            x.timeScaledRiskFreeRate).div(x.timeScaledVol);
        int256 d2 = d1 - x.timeScaledVol;

        int256 sign = isCall ? ONE : -ONE;

        int256 a = spot.mul(normalCdf(d1.mul(sign)));
        int256 b = strike.div(x.discountFactor).mul(normalCdf(d2.mul(sign)));
        price = (a - b).mul(sign);
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
        int256 five = 5e18;
        int256 ten = 10e18;

        int256 o = spot.log10().floor();

        int256 x = spot.mul(ten.pow(o.mul(-ONE) - ONE));

        int256 f = ten.pow(o - ONE);
        int256 y = x < 0.5e18 ? ONE.mul(f) : five.mul(f);
        return spot < 1000e18 ? y : y.ceil();
    }
}
