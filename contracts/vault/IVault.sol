// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IVault {
    event UpdateQuotes();

    function getQuote(address pool, uint256 size, bool isBuy) external view returns (uint256 maxSize, uint256 price);
    function fillQuote(address pool, uint256 size, bool isBuy) external;
}
