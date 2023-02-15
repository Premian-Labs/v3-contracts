// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {SD59x18} from "./prbMath/SD59x18.sol";
import {UD60x18} from "./prbMath/UD60x18.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    using SafeCast for uint256;
    using SafeCast for int256;
    using UD60x18 for uint256;
    using SD59x18 for int256;

    // To prevent stack too deep
    struct BlackScholesPriceVarsInternal {
        int256 discountFactor;
        int256 timeScaledVol;
        int256 timeScaledVar;
        int256 timeScaledRiskFreeRate;
    }

    uint256 internal constant ONE_HALF = 0.5e18;
    uint256 internal constant ONE = 1e18;
    uint256 internal constant TWO = 2e18;
    uint256 internal constant FIVE = 5e18;
    uint256 internal constant TEN = 10e18;
    uint256 internal constant ONE_THOUSAND = 1000e18;
    uint256 internal constant INITIALIZATION_ALPHA = 5e18;
    uint256 internal constant ATM_MONEYNESS = 0.5e18;
    uint256 internal constant NEAR_TERM_TTM = 14 days;
    uint256 internal constant ONE_YEAR_TTM = 365 days;
    uint256 internal constant FEE_SCALAR = 100e18;

    int256 internal constant ONE_HALF_I = 0.5e18;
    int256 internal constant ONE_I = 1e18;
    int256 internal constant TWO_I = 2e18;
    int256 internal constant FOUR_I = 4e18;
    int256 internal constant TEN_I = 10e18;
    int256 internal constant ALPHA = -6.37309208e18;
    int256 internal constant LAMBDA = -0.61228883e18;
    int256 internal constant S1 = -0.11105481e18;
    int256 internal constant S2 = 0.44334159e18;
    int256 internal constant SQRT_2PI = 2_506628274631000502;

    /// @notice Helper function to evaluate used to compute the normal CDF approximation
    /// @param x 59x18 fixed point representation of the input to the normal CDF
    /// @return result 59x18 fixed point representation of the value of the evaluated helper function
    function helperNormal(int256 x) internal pure returns (int256 result) {
        int256 a = ALPHA.div(LAMBDA).mul(S1);
        int256 b = (S1.mul(x) + ONE_I).pow(LAMBDA.div(S1)) - ONE_I;
        result = (a.mul(b) + S2.mul(x)).exp().mul(-(TWO_I.ln())).exp();
    }

    /// @notice Approximation of the normal CDF
    /// @dev The approximation implemented is based on the paper
    /// 'Accurate RMM-Based Approximations for the CDF of the Normal Distribution'
    /// by Haim Shore
    /// @param x input value to evaluate the normal CDF on, F(Z<=x)
    /// @return result SD59x18 fixed point representation of the normal CDF evaluated at x
    function normalCdf(int256 x) internal pure returns (int256 result) {
        result = ((ONE_I + helperNormal(-x)) - helperNormal(x)).div(TWO_I);
    }

    /// @notice Approximation of the Probability Density Function.
    /// @dev Equal to `Z(x) = (1 / σ√2π)e^( (-(x - µ)^2) / 2σ^2 )`.
    ///      Only computes pdf of a distribution with µ = 0 and σ = 1.
    /// @custom:error Maximum error of 1.2e-7.
    /// @custom:source https://mathworld.wolfram.com/ProbabilityDensityFunction.html.
    /// @param x 60x18 fixed point number to get PDF for
    /// @return z 60x18 fixed point z-number
    function normalPdf(int256 x) internal pure returns (int256 z) {
        int256 e;
        assembly {
            e := sdiv(mul(add(not(x), 1), x), TWO) // (-x * x) / 2.
        }
        e = e.exp();
        assembly {
            z := sdiv(mul(e, ONE_I), SQRT_2PI)
        }
    }

    /// @notice Implementation of the ReLu function f(x)=(x)^+ to compute call / put payoffs
    /// @param x SD59x18 input value to evaluate the
    /// @return result SD59x18 output of the relu function
    function relu(int256 x) internal pure returns (uint256) {
        if (x >= 0) {
            return x.toUint256();
        }
        return 0;
    }

    function d1d2(
        uint256 spot,
        uint256 strike,
        uint256 timeToMaturity,
        uint256 volAnnualized,
        uint256 riskFreeRate
    ) internal pure returns (int256 d1, int256 d2) {
        uint256 timeScaledVol = timeToMaturity.mul(volAnnualized);
        uint256 timeScaledVar = timeScaledVol.pow(TWO);
        uint256 timeScaledRiskFreeRate = timeToMaturity.mul(riskFreeRate);

        d1 =
            spot.div(strike).toInt256().ln() +
            timeScaledVar.div(TWO).toInt256() +
            timeScaledRiskFreeRate.div(timeScaledVol).toInt256();
        d2 = d1 - timeScaledVol.toInt256();
    }

    /// @notice Calculate the price of an option using the Black-Scholes model
    /// @dev this implementation assumes zero interest
    /// @param spot 60x18 fixed point representation of spot price
    /// @param strike 60x18 fixed point representation of strike price
    /// @param timeToMaturity 60x18 fixed point representation of duration of option contract (in years)
    /// @param volAnnualized 60x18 fixed point representation of annualized volatility
    /// @param riskFreeRate 60x18 fixed point representation the risk-free frate
    /// @param isCall whether to price "call" or "put" option
    /// @return price 60x18 fixed point representation of Black-Scholes option price
    function blackScholesPrice(
        uint256 spot,
        uint256 strike,
        uint256 timeToMaturity,
        uint256 volAnnualized,
        uint256 riskFreeRate,
        bool isCall
    ) internal pure returns (uint256) {
        int256 _spot = spot.toInt256();
        int256 _strike = strike.toInt256();

        if (timeToMaturity == 0) {
            if (isCall) {
                return relu(_spot - _strike);
            }
            return relu(_strike - _spot);
        }

        int256 discountFactor;
        if (riskFreeRate > 0) {
            discountFactor = riskFreeRate.mul(timeToMaturity).toInt256().exp();
        } else {
            discountFactor = ONE_I;
        }

        if (volAnnualized == 0) {
            if (isCall) {
                return relu(_spot - _strike.div(discountFactor));
            }
            return relu(_strike.div(discountFactor) - _spot);
        }

        (int256 d1, int256 d2) = d1d2(
            spot,
            strike,
            timeToMaturity,
            volAnnualized,
            riskFreeRate
        );
        int256 sign = isCall ? ONE_I : -ONE_I;
        int256 a = _spot.mul(normalCdf(d1.mul(sign)));
        int256 b = _strike.div(discountFactor).mul(normalCdf(d2.mul(sign)));

        return (a - b).mul(sign).toUint256();
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
        uint256 spot
    ) internal pure returns (uint256) {
        int256 o = spot.toInt256().log10().floor();
        int256 x = spot.toInt256().mul(TEN_I.pow(o.mul(-ONE_I) - ONE_I));
        uint256 f = TEN_I.pow(o - ONE_I).toUint256();
        uint256 y = x.toUint256() < ONE_HALF ? ONE.mul(f) : FIVE.mul(f);
        return spot < ONE_THOUSAND ? y : y.ceil();
    }

    /// @notice Calculate the log moneyness of a strike/spot price pair
    /// @param spot 60x18 fixed point representation of spot price
    /// @param strike 60x18 fixed point representation of strike price
    /// @return The log moneyness of the strike price
    function logMoneyness(
        uint256 spot,
        uint256 strike
    ) internal pure returns (uint256) {
        return spot.div(strike).toInt256().ln().abs().toUint256();
    }

    function initializationFee(
        uint256 spot,
        uint256 strike,
        uint64 maturity
    ) internal view returns (uint256) {
        uint256 moneyness = logMoneyness(spot, strike);
        uint256 timeToMaturity = calculateTimeToMaturity(maturity);
        uint256 kBase = moneyness < ATM_MONEYNESS
            ? (ATM_MONEYNESS - moneyness).toInt256().pow(FOUR_I).toUint256()
            : moneyness - ATM_MONEYNESS;
        uint256 tBase = timeToMaturity < NEAR_TERM_TTM
            ? 3 * (NEAR_TERM_TTM - timeToMaturity) + NEAR_TERM_TTM
            : timeToMaturity;
        uint256 scaledT = tBase.div(ONE_YEAR_TTM).sqrt();

        return
            INITIALIZATION_ALPHA.mul(kBase + scaledT).mul(scaledT).mul(
                FEE_SCALAR
            );
    }
}
