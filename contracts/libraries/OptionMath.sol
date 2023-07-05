// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {BokkyPooBahsDateTimeLibrary as DateTime} from "@bokkypoobah/BokkyPooBahsDateTimeLibrary.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {ZERO, ONE_HALF, ONE, TWO, FIVE, TEN, ONE_THOUSAND, iZERO, iONE_HALF, iONE, iTWO, iFOUR, iEIGHT, iNINE, iTEN} from "./Constants.sol";

library OptionMath {
    struct BlackScholesPriceVarsInternal {
        int256 discountFactor;
        int256 timeScaledVol;
        int256 timeScaledVar;
        int256 timeScaledRiskFreeRate;
    }

    UD60x18 internal constant INITIALIZATION_ALPHA = UD60x18.wrap(5e18);
    UD60x18 internal constant ATM_MONEYNESS = UD60x18.wrap(0.5e18);
    uint256 internal constant NEAR_TERM_TTM = 14 days;
    uint256 internal constant ONE_YEAR_TTM = 365 days;
    UD60x18 internal constant FEE_SCALAR = UD60x18.wrap(100e18);

    SD59x18 internal constant ALPHA = SD59x18.wrap(-6.37309208e18);
    SD59x18 internal constant LAMBDA = SD59x18.wrap(-0.61228883e18);
    SD59x18 internal constant S1 = SD59x18.wrap(-0.11105481e18);
    SD59x18 internal constant S2 = SD59x18.wrap(0.44334159e18);
    int256 internal constant SQRT_2PI = 2_506628274631000502;

    UD60x18 internal constant MIN_INPUT_PRICE = UD60x18.wrap(1e1);
    UD60x18 internal constant MAX_INPUT_PRICE = UD60x18.wrap(1e34);
    SD59x18 internal constant iERROR_MARGIN = SD59x18.wrap(1e2);

    error OptionMath__NonPositiveVol();
    error OptionMath__OutOfBoundsPrice(UD60x18 min, UD60x18 max, UD60x18 price);
    error OptionMath__Underflow();

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
    /// @dev Equal to `Z(x) = (1 / σ√2π)e^( (-(x - µ)^2) / 2σ^2 )`. Only computes pdf of a distribution with µ = 0 and
    ///      σ = 1.
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

    /// @notice Implementation of the ReLu function f(x)=(x)^+ to compute call / put payoffs
    /// @param x Input value (18 decimals)
    /// @return result Output of the relu function (18 decimals)
    function relu(SD59x18 x) internal pure returns (UD60x18) {
        if (x >= iZERO) {
            return x.intoUD60x18();
        }
        return ZERO;
    }

    /// @notice Returns the terms d1 and d2 from the Black-Scholes formula that are used
    ///         to compute the price of a call / put option.
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

        if (scaledPrice < SD59x18.wrap(-1e12)) revert OptionMath__Underflow();
        if (scaledPrice >= SD59x18.wrap(-1e12) && scaledPrice <= iZERO) scaledPrice = iZERO;

        return (scaledPrice * _strike).intoUD60x18();
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
        if (lastDayOfMonth - dayOfMonth > 7) return false;
        return isFriday(maturity);
    }

    /// @notice Calculates the time to maturity in seconds
    /// @param maturity The maturity timestamp of the option
    /// @return Time to maturity in seconds
    function calculateTimeToMaturity(uint256 maturity) internal view returns (uint256) {
        return maturity - block.timestamp;
    }

    /// @notice Calculates the strike interval for the given spot price
    /// @param spot The spot price of the base asset (18 decimals)
    /// @return The strike interval (18 decimals)
    function calculateStrikeInterval(UD60x18 spot) internal pure returns (UD60x18) {
        if (spot < MIN_INPUT_PRICE || spot > MAX_INPUT_PRICE)
            revert OptionMath__OutOfBoundsPrice(MIN_INPUT_PRICE, MAX_INPUT_PRICE, spot);

        SD59x18 o = zCount(spot);
        SD59x18 x = spot.intoSD59x18() * (iTEN.pow(o * (-iONE) - iONE));
        UD60x18 f = iTEN.pow(o - iONE).intoUD60x18();

        UD60x18 y;
        if (iONE_HALF > x) {
            // NOTE: `x` may be below `0.5e18` due to rounding errors, in which case, we correct it. This has been
            // observed when `5e15 >= spot`.
            if (ud(5e15) >= spot && iERROR_MARGIN > iONE_HALF - x) y = FIVE * f;
            else y = ONE * f;
        } else y = FIVE * f;

        return ONE_THOUSAND > spot ? y : y.ceil();
    }

    /// @notice Calculate the log moneyness of a strike/spot price pair
    /// @param spot The spot price (18 decimals)
    /// @param strike The strike price (18 decimals)
    /// @return The log moneyness of the strike price (18 decimals)
    function logMoneyness(UD60x18 spot, UD60x18 strike) internal pure returns (UD60x18) {
        return (spot / strike).intoSD59x18().ln().abs().intoUD60x18();
    }

    /// @notice Calculate the initialization fee for a pool
    /// @param spot The spot price (18 decimals)
    /// @param strike The strike price (18 decimals)
    /// @param maturity The maturity timestamp of the option
    /// @return The initialization fee (18 decimals)
    function initializationFee(UD60x18 spot, UD60x18 strike, uint256 maturity) internal view returns (UD60x18) {
        UD60x18 moneyness = logMoneyness(spot, strike);
        uint256 timeToMaturity = calculateTimeToMaturity(maturity);
        UD60x18 kBase = moneyness < ATM_MONEYNESS
            ? (ATM_MONEYNESS - moneyness).intoSD59x18().pow(iFOUR).intoUD60x18()
            : moneyness - ATM_MONEYNESS;
        uint256 tBase = timeToMaturity < NEAR_TERM_TTM
            ? 3 * (NEAR_TERM_TTM - timeToMaturity) + NEAR_TERM_TTM
            : timeToMaturity;
        UD60x18 scaledT = (ud(tBase * 1e18) / ud(ONE_YEAR_TTM * 1e18)).sqrt();

        return INITIALIZATION_ALPHA * (kBase + scaledT) * scaledT * FEE_SCALAR;
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

    /// @notice Counts the number of digits in the given input
    function zCount(UD60x18 input) internal pure returns (SD59x18) {
        uint256 _input = input.unwrap();
        int256 z = -18;

        while (_input >= 10) {
            _input /= 10;
            z++;
        }

        return sd(z * int256(1e18));
    }
}
