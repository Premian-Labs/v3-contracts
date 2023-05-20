// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {VolatilityOracle} from "../../oracle/VolatilityOracle.sol";
import {VolatilityOracleStorage} from "../../oracle/VolatilityOracleStorage.sol";

contract VolatilityOracleMock is VolatilityOracle {
    using VolatilityOracleStorage for VolatilityOracleStorage.Layout;

    mapping(bytes32 => UD60x18) internal volatilityMap;
    UD60x18 internal riskFreeRate;

    function findInterval(
        SD59x18[5] memory arr,
        SD59x18 value
    ) external pure returns (uint256) {
        return VolatilityOracle._findInterval(arr, value);
    }

    function getRiskFreeRate() external view override returns (UD60x18) {
        if (riskFreeRate != ud(0)) return riskFreeRate;

        return VolatilityOracleStorage.layout().riskFreeRate;
    }

    function setRiskFreeRate(UD60x18 value) external {
        riskFreeRate = value;
    }

    function setVolatility(
        address token,
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity,
        UD60x18 volatility
    ) external {
        volatilityMap[
            keccak256(abi.encode(token, spot, strike, timeToMaturity))
        ] = volatility;
    }

    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity
    ) public view override returns (UD60x18) {
        UD60x18 volatility = volatilityMap[
            keccak256(abi.encode(token, spot, strike, timeToMaturity))
        ];

        if (volatility != ud(0)) return volatility;

        return super.getVolatility(token, spot, strike, timeToMaturity);
    }

    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18[] memory strike,
        UD60x18[] memory timeToMaturity
    ) external view override returns (UD60x18[] memory) {
        UD60x18[] memory result = new UD60x18[](strike.length);

        for (uint256 i = 0; i < strike.length; i++) {
            result[i] = volatilityMap[
                keccak256(abi.encode(token, spot, strike[i], timeToMaturity[i]))
            ];

            if (result[i] == ud(0)) {
                result[i] = super.getVolatility(
                    token,
                    spot,
                    strike[i],
                    timeToMaturity[i]
                );
            }
        }

        return result;
    }
}
