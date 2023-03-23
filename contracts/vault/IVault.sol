// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IVault {
    event UpdateQuotes();

    function getTradeQuote(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external view returns (uint256 maxSize, uint256 price);

    function trade(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external;
}
