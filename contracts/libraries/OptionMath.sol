// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {BokkyPooBahsDateTimeLibrary as DateTime} from "@bokkypoobah/BokkyPooBahsDateTimeLibrary.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {PRBMathExtra} from "./PRBMathExtra.sol";

import {ZERO, ONE, TWO, iZERO, iONE, iTWO, iNINE} from "./Constants.sol";

library OptionMath {
    struct BlackScholesPriceVarsInternal {
        int256 discountFactor;
        int256 timeScaledVol;
        int256 timeScaledVar;
        int256 timeScaledRiskFreeRate;
    }

    SD59x18 internal constant ALPHA = sd(-6.37309208e18);
    SD59x18 internal constant LAMBDA = sd(-0.61228883e18);
    SD59x18 internal constant S1 = sd(-0.11105481e18);
    SD59x18 internal constant S2 = sd(0.44334159e18);
    int256 internal constant SQRT_2PI = 2_506628274631000502;

    UD60x18 internal constant MIN_INPUT_PRICE = ud(1e1);
    UD60x18 internal constant MAX_INPUT_PRICE = ud(1e34);

    error OptionMath__NonPositiveVol();
    error OptionMath__OutOfBoundsPrice(UD60x18 min, UD60x18 max, UD60x18 price);
    error OptionMath__Underflow();
    error OptionMath__UtilisationOutOfBounds();

    /// @notice Helper function to evaluate used to compute the normal CDF approximation
    /// @param x The input to the normal CDF (18 decimals)
    /// @return result The value of the evaluated helper function (18 decimals)
    function helperNormal(SD59x18 x) internal pure returns (SD59x18 result) {
        SD59x18 a = (ALPHA / LAMBDA) * S1;
        SD59x18 b = (S1 * x + iONE).pow(LAMBDA / S1) - iONE;
        result = ((a * b + S2 * x).exp() * (-iTWO.ln())).exp();
    }

    /// @notice Approximation of the normal CDF
    /// @dev The approximation implemented is based on the paper 'Accurate RMM-Based Approximations for the CDF of the
    ///      Normal Distribution' by Haim Shore
    /// @param x input value to evaluate the normal CDF on, F(Z<=x) (18 decimals)
    /// @return result The normal CDF evaluated at x (18 decimals)
    function normalCdf(SD59x18 x) internal pure returns (SD59x18 result) {
        if (x <= -iNINE) {
            result = iZERO;
        } else if (x >= iNINE) {
            result = iONE;
        } else {
            result = ((iONE + helperNormal(-x)) - helperNormal(x)) / iTWO;
        }
    }

    /// @notice Normal Distribution Probability Density Function.
    /// @dev Equal to `Z(x) = (1 / σ√2π)e^( (-(x - µ)^2) / 2σ^2 )`. Only computes pdf of a distribution with `µ = 0` and
    ///      `σ = 1`.
    /// @custom:error Maximum error of 1.2e-7.
    /// @custom:source https://mathworld.wolfram.com/ProbabilityDensityFunction.html.
    /// @param x Number to get PDF for (18 decimals)
    /// @return z z-number (18 decimals)
    function normalPdf(SD59x18 x) internal pure returns (SD59x18 z) {
        SD59x18 e;
        int256 one = iONE.unwrap();
        uint256 two = TWO.unwrap();

        assembly {
            e := sdiv(mul(add(not(x), 1), x), two) // (-x * x) / 2.
        }
        e = e.exp();
        assembly {
            z := sdiv(mul(e, one), SQRT_2PI)
        }
    }

    /// @notice Implementation of the ReLu function `f(x)=(x)^+` to compute call / put payoffs
    /// @param x Input value (18 decimals)
    /// @return result Output of the relu function (18 decimals)
    function relu(SD59x18 x) internal pure returns (UD60x18) {
        if (x >= iZERO) {
            return x.intoUD60x18();
        }
        return ZERO;
    }

    /// @notice Returns the terms `d1` and `d2` from the Black-Scholes formula that are used to compute the price of a
    ///         call / put option.
    /// @param spot The spot price. (18 decimals)
    /// @param strike The strike price of the option. (18 decimals)
    /// @param timeToMaturity The time until the option expires. (18 decimals)
    /// @param volAnnualized The percentage volatility of the geometric Brownian motion. (18 decimals)
    /// @param riskFreeRate The rate of the risk-less asset, i.e. the risk-free interest rate. (18 decimals)
    /// @return d1 The term d1 from the Black-Scholes formula. (18 decimals)
    /// @return d2 The term d2 from the Black-Scholes formula. (18 decimals)
    function d1d2(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate
    ) internal pure returns (SD59x18 d1, SD59x18 d2) {
        UD60x18 timeScaledRiskFreeRate = riskFreeRate * timeToMaturity;
        UD60x18 timeScaledVariance = (volAnnualized.powu(2) / TWO) * timeToMaturity;
        UD60x18 timeScaledStd = volAnnualized * timeToMaturity.sqrt();
        SD59x18 lnSpot = (spot / strike).intoSD59x18().ln();

        d1 =
            (lnSpot + timeScaledVariance.intoSD59x18() + timeScaledRiskFreeRate.intoSD59x18()) /
            timeScaledStd.intoSD59x18();

        d2 = d1 - timeScaledStd.intoSD59x18();
    }

    /// @notice Calculate option delta
    /// @param spot Spot price
    /// @param strike Strike price
    /// @param timeToMaturity Duration of option contract (in years)
    /// @param volAnnualized Annualized volatility
    /// @param isCall whether to price "call" or "put" option
    /// @return price Option delta
    function optionDelta(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate,
        bool isCall
    ) internal pure returns (SD59x18) {
        (SD59x18 d1, ) = d1d2(spot, strike, timeToMaturity, volAnnualized, riskFreeRate);

        if (isCall) {
            return normalCdf(d1);
        } else {
            return -normalCdf(-d1);
        }
    }

    /// @notice Calculate the price of an option using the Black-Scholes model
    /// @dev this implementation assumes zero interest
    /// @param spot Spot price (18 decimals)
    /// @param strike Strike price (18 decimals)
    /// @param timeToMaturity Duration of option contract (in years) (18 decimals)
    /// @param volAnnualized Annualized volatility (18 decimals)
    /// @param riskFreeRate The risk-free rate (18 decimals)
    /// @param isCall whether to price "call" or "put" option
    /// @return price The Black-Scholes option price (18 decimals)
    function blackScholesPrice(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate,
        bool isCall
    ) internal pure returns (UD60x18) {
        SD59x18 _spot = spot.intoSD59x18();
        SD59x18 _strike = strike.intoSD59x18();
        if (volAnnualized == ZERO) revert OptionMath__NonPositiveVol();

        if (timeToMaturity == ZERO) {
            if (isCall) {
                return relu(_spot - _strike);
            }
            return relu(_strike - _spot);
        }

        SD59x18 discountFactor;
        if (riskFreeRate > ZERO) {
            discountFactor = (riskFreeRate * timeToMaturity).intoSD59x18().exp();
        } else {
            discountFactor = iONE;
        }

        (SD59x18 d1, SD59x18 d2) = d1d2(spot, strike, timeToMaturity, volAnnualized, riskFreeRate);
        SD59x18 sign = isCall ? iONE : -iONE;
        SD59x18 a = (_spot / _strike) * normalCdf(d1 * sign);
        SD59x18 b = normalCdf(d2 * sign) / discountFactor;
        SD59x18 scaledPrice = (a - b) * sign;

        if (scaledPrice < sd(-1e12)) revert OptionMath__Underflow();
        if (scaledPrice >= sd(-1e12) && scaledPrice <= iZERO) scaledPrice = iZERO;

        return (scaledPrice * _strike).intoUD60x18();
    }

    /// @notice Returns true if the maturity time is 8AM UTC
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity time is 8AM UTC, false otherwise
    function is8AMUTC(uint256 maturity) internal pure returns (bool) {
        return maturity % 24 hours == 8 hours;
    }

    /// @notice Returns true if the maturity day is Friday
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is Friday, false otherwise
    function isFriday(uint256 maturity) internal pure returns (bool) {
        return DateTime.getDayOfWeek(maturity) == DateTime.DOW_FRI;
    }

    /// @notice Returns true if the maturity day is the last Friday of the month
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is the last Friday of the month, false otherwise
    function isLastFriday(uint256 maturity) internal pure returns (bool) {
        uint256 dayOfMonth = DateTime.getDay(maturity);
        uint256 lastDayOfMonth = DateTime.getDaysInMonth(maturity);
        if (lastDayOfMonth - dayOfMonth >= 7) return false;
        return isFriday(maturity);
    }

    /// @notice Calculates the time to maturity in seconds
    /// @param maturity The maturity timestamp of the option
    /// @return Time to maturity in seconds
    function calculateTimeToMaturity(uint256 maturity) internal view returns (uint256) {
        return maturity - block.timestamp;
    }

    /// @notice Calculates the strike interval for `strike`
    /// @param strike The price to calculate strike interval for (18 decimals)
    /// @return The strike interval (18 decimals)
    function calculateStrikeInterval(UD60x18 strike) internal pure returns (UD60x18) {
        if (strike < MIN_INPUT_PRICE || strike > MAX_INPUT_PRICE)
            revert OptionMath__OutOfBoundsPrice(MIN_INPUT_PRICE, MAX_INPUT_PRICE, strike);

        uint256 _strike = strike.unwrap();
        uint256 exponent = log10Floor(_strike);
        uint256 multiplier = (_strike >= 5 * 10 ** exponent) ? 5 : 1;
        return ud(multiplier * 10 ** (exponent - 1));
    }

    /// @notice Rounds `strike` using the calculated strike interval
    /// @param strike The price to round (18 decimals)
    /// @return The rounded strike price (18 decimals)
    function roundToStrikeInterval(UD60x18 strike) internal pure returns (UD60x18) {
        uint256 _strike = strike.div(ONE).unwrap();
        uint256 interval = calculateStrikeInterval(strike).div(ONE).unwrap();
        uint256 lower = interval * (_strike / interval);
        uint256 upper = interval * ((_strike / interval) + 1);
        return (_strike - lower < upper - _strike) ? ud(lower) : ud(upper);
    }

    /// @notice Converts a number with `inputDecimals`, to a number with given amount of decimals
    /// @param value The value to convert
    /// @param inputDecimals The amount of decimals the input value has
    /// @param targetDecimals The amount of decimals to convert to
    /// @return The converted value
    function scaleDecimals(uint256 value, uint8 inputDecimals, uint8 targetDecimals) internal pure returns (uint256) {
        if (targetDecimals == inputDecimals) return value;
        if (targetDecimals > inputDecimals) return value * (10 ** (targetDecimals - inputDecimals));

        return value / (10 ** (inputDecimals - targetDecimals));
    }

    /// @notice Converts a number with `inputDecimals`, to a number with given amount of decimals
    /// @param value The value to convert
    /// @param inputDecimals The amount of decimals the input value has
    /// @param targetDecimals The amount of decimals to convert to
    /// @return The converted value
    function scaleDecimals(int256 value, uint8 inputDecimals, uint8 targetDecimals) internal pure returns (int256) {
        if (targetDecimals == inputDecimals) return value;
        if (targetDecimals > inputDecimals) return value * int256(10 ** (targetDecimals - inputDecimals));

        return value / int256(10 ** (inputDecimals - targetDecimals));
    }

    /// @notice Performs a naive log10 calculation on `input` returning the floor of the result
    function log10Floor(uint256 input) internal pure returns (uint256 count) {
        while (input >= 10) {
            input /= 10;
            count++;
        }

        return count;
    }

    /// @notice Calculates the C-level given a utilisation value and time since last trade value (duration).
    ///         (https://www.desmos.com/calculator/0uzv50t7jy)
    /// @param utilisation The utilisation after some collateral is utilised
    /// @param duration The time since last trade (hours)
    /// @param alpha (needs to be filled in)
    /// @param minCLevel The minimum C-level
    /// @param maxCLevel The maximum C-level
    /// @param decayRate The decay rate of the C-level back down to minimum level (decay/hour)
    /// @return The C-level corresponding to the post-utilisation value.
    function computeCLevel(
        UD60x18 utilisation,
        UD60x18 duration,
        UD60x18 alpha,
        UD60x18 minCLevel,
        UD60x18 maxCLevel,
        UD60x18 decayRate
    ) internal pure returns (UD60x18) {
        if (utilisation > ONE) revert OptionMath__UtilisationOutOfBounds();

        UD60x18 posExp = (alpha * (ONE - utilisation)).exp();
        UD60x18 alphaExp = alpha.exp();
        UD60x18 k = (alpha * (minCLevel * alphaExp - maxCLevel)) / (alphaExp - ONE);

        UD60x18 cLevel = (k * posExp + maxCLevel * alpha - k) / (alpha * posExp);
        UD60x18 decay = decayRate * duration;

        return PRBMathExtra.max(cLevel <= decay ? ZERO : cLevel - decay, minCLevel);
    }

    /// @notice Calculates the geo-mean C-level given a utilisation before and after collateral is utilised.
    /// @param utilisationBefore The utilisation before some collateral is utilised.
    /// @param utilisationAfter The utilisation after some collateral is utilised
    /// @param duration The time since last trade (hours)
    /// @param alpha (needs to be filled in)
    /// @param minCLevel The minimum C-level
    /// @param maxCLevel The maximum C-level
    /// @param decayRate The decay rate of the C-level back down to minimum level (decay/hour)
    /// @return cLevel The C-level corresponding to the geo-mean of the utilisation value before and after collateral is utilised.
    function computeCLevelGeoMean(
        UD60x18 utilisationBefore,
        UD60x18 utilisationAfter,
        UD60x18 duration,
        UD60x18 alpha,
        UD60x18 minCLevel,
        UD60x18 maxCLevel,
        UD60x18 decayRate
    ) internal pure returns (UD60x18 cLevel) {
        UD60x18 cLevelBefore = computeCLevel(utilisationBefore, ZERO, alpha, minCLevel, maxCLevel, decayRate);

        UD60x18 cLevelAfter = computeCLevel(utilisationAfter, duration, alpha, minCLevel, maxCLevel, decayRate);

        cLevel = (cLevelBefore * cLevelAfter).sqrt();
    }
}
