// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath, SD59x18} from "../../libraries/OptionMath.sol";

contract OptionMathMock {
    function strikeInterval(
        SD59x18 beta,
        SD59x18 spot
    ) external pure returns (SD59x18) {
        return OptionMath.strikeInterval(beta, spot);
    }
}
