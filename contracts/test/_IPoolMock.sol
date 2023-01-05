// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Position} from "../libraries/Position.sol";

interface _IPoolMock {
    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId);

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (
            uint8 version,
            address operator,
            uint256 lower,
            uint256 upper,
            Position.OrderType orderType
        );

    function amountOfTicksBetween(
        uint256 lower,
        uint256 upper
    ) external pure returns (uint256);
}
