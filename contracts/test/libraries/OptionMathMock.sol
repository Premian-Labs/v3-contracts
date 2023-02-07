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

    function relu(int256 x) external pure returns (int256) {
        return OptionMath.relu(x);
    }

    function blackScholesPrice(
        int256 spot59x18,
        int256 strike59x18,
        int256 timeToMaturity59x18,
        int256 volAnnualized59x18,
        int256 riskFreeRate59x18,
        bool isCall
    ) external pure returns (int256) {
        return
            OptionMath.blackScholesPrice(
                spot59x18,
                strike59x18,
                timeToMaturity59x18,
                volAnnualized59x18,
                riskFreeRate59x18,
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
        int256 spot
    ) external pure returns (int256) {
        return OptionMath.calculateStrikeInterval(spot);
    }
}
