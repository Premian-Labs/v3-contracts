// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath, SD59x18} from "../../libraries/OptionMath.sol";

contract OptionMathMock {
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
