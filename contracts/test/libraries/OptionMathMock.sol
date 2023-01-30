// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OptionMath, SD59x18} from "../../libraries/OptionMath.sol";

contract OptionMathMock {

    function helperNormal(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath._helperNormal(x);
    }

    function normalCdf(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath._normalCdf(x);
    }

    function relu(SD59x18 x) external pure returns (SD59x18) {
        return OptionMath._relu(x);
    }

    function blackScholesPrice(
        SD59x18 spot59x18,
        SD59x18 strike59x18,
        SD59x18 timeToMaturity59x18,
        SD59x18 varAnnualized59x18,
        bool isCall
    ) external pure returns (SD59x18) {
        return OptionMath._blackScholesPrice(
            spot59x18,
            strike59x18,
            timeToMaturity59x18,
            varAnnualized59x18,
            isCall
        );
    }

}