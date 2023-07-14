// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";

contract OracleAdapterMock {
    address internal immutable BASE;
    address internal immutable QUOTE;

    UD60x18 internal getPriceAmount;
    UD60x18 internal getPriceAtAmount;

    mapping(uint256 => UD60x18) internal getPriceAtAmountMap;

    constructor(address _base, address _quote, UD60x18 _getPriceAmount, UD60x18 _getPriceAtAmount) {
        BASE = _base;
        QUOTE = _quote;
        getPriceAmount = _getPriceAmount;
        getPriceAtAmount = _getPriceAtAmount;
    }

    function upsertPair(address tokenA, address tokenB) external {}

    function setPrice(UD60x18 _getPriceAmount) external {
        getPriceAmount = _getPriceAmount;
    }

    function setPriceAt(uint256 maturity, UD60x18 _getPriceAtAmount) external {
        getPriceAtAmountMap[maturity] = _getPriceAtAmount;
    }

    function setPriceAt(UD60x18 _getPriceAtAmount) external {
        getPriceAtAmount = _getPriceAtAmount;
    }

    function getPrice(address, address) external view returns (UD60x18) {
        return getPriceAmount;
    }

    function getPriceAt(address, address, uint256 maturity) external view returns (UD60x18) {
        if (getPriceAtAmountMap[maturity] != ud(0)) {
            return getPriceAtAmountMap[maturity];
        }

        return getPriceAtAmount;
    }

    function describePricingPath(
        address token
    ) external view returns (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) {
        adapterType = IOracleAdapter.AdapterType.Chainlink;

        path = new address[][](1);
        address[] memory aggregator = new address[](1);

        aggregator[0] = token == BASE
            ? 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
            : 0x158228e08C52F3e2211Ccbc8ec275FA93f6033FC;

        path[0] = aggregator;

        decimals = new uint8[](1);
        decimals[0] = 18;
    }
}
