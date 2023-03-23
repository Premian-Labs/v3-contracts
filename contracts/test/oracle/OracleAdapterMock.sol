// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {IOracleAdapter} from "../../oracle/price/IOracleAdapter.sol";

contract OracleAdapterMock {
    address immutable BASE;
    address immutable QUOTE;

    uint256 quoteAmount;
    uint256 quoteFromAmount;

    constructor(
        address _base,
        address _quote,
        uint256 _quoteAmount,
        uint256 _quoteFromAmount
    ) {
        BASE = _base;
        QUOTE = _quote;
        quoteAmount = _quoteAmount;
        quoteFromAmount = _quoteFromAmount;
    }

    function upsertPair(address tokenA, address tokenB) external {}

    function setQuote(uint256 _quoteAmount) external {
        quoteAmount = _quoteAmount;
    }

    function setQuoteFrom(uint256 _quoteFromAmount) external {
        quoteFromAmount = _quoteFromAmount;
    }

    function quote(address, address) external view returns (uint256) {
        return quoteAmount;
    }

    function quoteFrom(
        address,
        address,
        uint256
    ) external view returns (uint256) {
        return quoteFromAmount;
    }

    function describePricingPath(
        address token
    )
        external
        view
        returns (
            IOracleAdapter.AdapterType adapterType,
            address[][] memory path,
            uint8[] memory decimals
        )
    {
        path = new address[][](1);
        address[] memory aggregator = new address[](1);
        decimals = new uint8[](1);

        decimals[0] = 8;

        if (token == BASE) {
            aggregator[0] = 0x37bC7498f4FF12C19678ee8fE19d713b87F6a9e6;
            path[0] = aggregator;

            return (IOracleAdapter.AdapterType.CHAINLINK, path, decimals);
        } else {
            aggregator[0] = 0xDEc0a100eaD1fAa37407f0Edc76033426CF90b82;
            path[0] = aggregator;

            return (IOracleAdapter.AdapterType.CHAINLINK, path, decimals);
        }
    }
}
