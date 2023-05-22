// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";

contract OracleAdapterMock {
    address internal immutable BASE;
    address internal immutable QUOTE;

    UD60x18 internal quoteAmount;
    UD60x18 internal quoteFromAmount;

    mapping(uint256 => UD60x18) internal quoteFromAmountMap;

    constructor(address _base, address _quote, UD60x18 _quoteAmount, UD60x18 _quoteFromAmount) {
        BASE = _base;
        QUOTE = _quote;
        quoteAmount = _quoteAmount;
        quoteFromAmount = _quoteFromAmount;
    }

    function upsertPair(address tokenA, address tokenB) external {}

    function setQuote(UD60x18 _quoteAmount) external {
        quoteAmount = _quoteAmount;
    }

    function setQuoteFrom(uint256 maturity, UD60x18 _quoteFromAmount) external {
        quoteFromAmountMap[maturity] = _quoteFromAmount;
    }

    function setQuoteFrom(UD60x18 _quoteFromAmount) external {
        quoteFromAmount = _quoteFromAmount;
    }

    function quote(address, address) external view returns (UD60x18) {
        return quoteAmount;
    }

    function quoteFrom(address, address, uint256 maturity) external view returns (UD60x18) {
        if (quoteFromAmountMap[maturity] != ud(0)) {
            return quoteFromAmountMap[maturity];
        }

        return quoteFromAmount;
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
