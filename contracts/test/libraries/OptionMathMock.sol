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
        uint256 spot60x18,
        uint256 strike60x18,
        uint256 timeToMaturity60x18,
        uint256 volAnnualized60x18,
        uint256 riskFreeRate60x18,
        bool isCall
    ) external pure returns (uint256) {
        return
            OptionMath.blackScholesPrice(
                spot60x18,
                strike60x18,
                timeToMaturity60x18,
                volAnnualized60x18,
                riskFreeRate60x18,
                isCall
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

    function estimateImpliedVolatility(
        bool isCall,
        uint256 optionPrice,
        uint256 spot,
        uint256 strike,
        uint64 maturity,
        uint256 riskFreeRate,
        uint256 estimateIv,
        uint256 errorBound
    ) internal view returns (uint256) {
        return OptionMath.estimateImpliedVolatility(
            isCall,
            optionPrice,
            spot,
            strike,
            maturity,
            riskFreeRate,
            estimateIv,
            errorBound
        );
    }
}
