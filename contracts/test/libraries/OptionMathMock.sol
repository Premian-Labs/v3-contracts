// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath, SD59x18} from "../../libraries/OptionMath.sol";

contract OptionMathMock {
    function calculateStrikeInterval(
        int256 spot
    ) external pure returns (int256) {
        return OptionMath.calculateStrikeInterval(spot);
    }
}
