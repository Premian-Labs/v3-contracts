// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18} from "@prb/math/src/SD59x18.sol";

import {VolatilityOracle} from "../../oracle/volatility/VolatilityOracle.sol";

contract VolatilityOracleMock is VolatilityOracle {
    function findInterval(
        SD59x18[] memory arr,
        SD59x18 value
    ) external pure returns (uint256) {
        return VolatilityOracle._findInterval(arr, value);
    }
}
