// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

contract UniswapV3AdapterProxy is ProxyUpgradeableOwnable {
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    /// @notice Thrown when cardinality per minute has not been set
    error UniswapV3AdapterProxy__CardinalityPerMinuteNotSet();

    /// @notice Thrown when period has not been set
    error UniswapV3AdapterProxy__PeriodNotSet();

    constructor(
        uint32 period,
        uint256 cardinalityPerMinute,
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        if (cardinalityPerMinute == 0) revert UniswapV3AdapterProxy__CardinalityPerMinuteNotSet();

        if (period == 0) revert UniswapV3AdapterProxy__PeriodNotSet();

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage.layout();

        l.targetCardinality = uint16((period * cardinalityPerMinute) / 60);
        l.cardinalityPerMinute = cardinalityPerMinute;
        l.period = period;

        l.feeTiers.push(100);
        l.feeTiers.push(500);
        l.feeTiers.push(3_000);
        l.feeTiers.push(10_000);
    }
}
