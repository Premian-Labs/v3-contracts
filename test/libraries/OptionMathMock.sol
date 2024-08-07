// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {OptionMath} from "contracts/libraries/OptionMath.sol";

contract OptionMathMock {
    function helperNormal(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath.helperNormal(x);
    }

    function normalCdf(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath.normalCdf(x);
    }

    function normalPdf(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath.normalPdf(x);
    }

    function relu(SD59x18 x) external pure returns (UD60x18) {
        return OptionMath.relu(x);
    }

    function optionDelta(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate,
        bool isCall
    ) external pure returns (SD59x18) {
        return OptionMath.optionDelta(spot, strike, timeToMaturity, volAnnualized, riskFreeRate, isCall);
    }

    function blackScholesPrice(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate,
        bool isCall
    ) external pure returns (UD60x18) {
        return OptionMath.blackScholesPrice(spot, strike, timeToMaturity, volAnnualized, riskFreeRate, isCall);
    }

    function d1d2(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volAnnualized,
        UD60x18 riskFreeRate
    ) external pure returns (SD59x18 d1, SD59x18 d2) {
        (d1, d2) = OptionMath.d1d2(spot, strike, timeToMaturity, volAnnualized, riskFreeRate);
    }

    function isFriday(uint256 maturity) external pure returns (bool) {
        return OptionMath.isFriday(maturity);
    }

    function isLastFriday(uint256 maturity) external pure returns (bool) {
        return OptionMath.isLastFriday(maturity);
    }

    function calculateTimeToMaturity(uint256 maturity) external view returns (uint256) {
        return OptionMath.calculateTimeToMaturity(maturity);
    }

    function calculateStrikeInterval(UD60x18 strike) external pure returns (UD60x18) {
        return OptionMath.calculateStrikeInterval(strike);
    }

    function countSignificantDigits(UD60x18 value) internal pure returns (uint8) {
        return OptionMath.countSignificantDigits(value);
    }
}
