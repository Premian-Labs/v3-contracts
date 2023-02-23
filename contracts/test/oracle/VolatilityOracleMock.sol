// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {VolatilityOracle} from "../../oracle/volatility/VolatilityOracle.sol";

contract VolatilityOracleMock is VolatilityOracle {
    function findInterval(
        int256[] memory arr,
        int256 value
    ) external pure returns (uint256) {
        return VolatilityOracle._findInterval(arr, value);
    }
}
