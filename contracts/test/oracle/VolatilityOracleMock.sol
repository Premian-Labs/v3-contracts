// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";

import {VolatilityOracle} from "../../oracle/VolatilityOracle.sol";

contract VolatilityOracleMock is VolatilityOracle {
    function findInterval(
        SD59x18[5] memory arr,
        SD59x18 value
    ) external pure returns (uint256) {
        return VolatilityOracle._findInterval(arr, value);
    }
}
