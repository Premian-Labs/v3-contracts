// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath} from "../../libraries/OptionMath.sol";

contract OptionMathMock {
    function helperNormal(int256 x) external pure returns (int256) {
        return OptionMath.helperNormal(x);
    }

    function normalCdf(int256 x) external pure returns (int256) {
        return OptionMath.normalCdf(x);
    }

    function normalPdf(int256 x) external pure returns (int256) {
        return OptionMath.normalPdf(x);
    }

    function relu(int256 x) external pure returns (uint256) {
        return OptionMath.relu(x);
    }

    function blackScholesPrice(
        uint256 spot,
        uint256 strike,
        uint256 timeToMaturity,
        uint256 volAnnualized,
        uint256 riskFreeRate,
        bool isCall
    ) external pure returns (uint256) {
        return
            OptionMath.blackScholesPrice(
                spot,
                strike,
                timeToMaturity,
                volAnnualized,
                riskFreeRate,
                isCall
            );
    }

    function d1d2(
        uint256 spot,
        uint256 strike,
        uint256 timeToMaturity,
        uint256 volAnnualized,
        uint256 riskFreeRate
    ) external pure returns (int256 d1, int256 d2) {
        (d1, d2) = OptionMath.d1d2(
            spot,
            strike,
            timeToMaturity,
            volAnnualized,
            riskFreeRate
        );
    }

    function isFriday(uint64 maturity) external pure returns (bool) {
        return OptionMath.isFriday(maturity);
    }

    function isLastFriday(uint64 maturity) external pure returns (bool) {
        return OptionMath.isLastFriday(maturity);
    }

    function calculateTimeToMaturity(
        uint64 maturity
    ) external view returns (uint256) {
        return OptionMath.calculateTimeToMaturity(maturity);
    }

    function calculateStrikeInterval(
        uint256 spot
    ) external pure returns (uint256) {
        return OptionMath.calculateStrikeInterval(spot);
    }

    function logMoneyness(
        uint256 spot,
        uint256 strike
    ) external pure returns (uint256) {
        return OptionMath.logMoneyness(spot, strike);
    }

    function initializationFee(
        uint256 spot,
        uint256 strike,
        uint64 maturity
    ) external view returns (uint256) {
        return OptionMath.initializationFee(spot, strike, maturity);
    }
}
