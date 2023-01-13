// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

interface IPoolCoreMock {
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

    // TODO : Move to PricingMock
    function fromPool(bool isBuy) external view returns (Pricing.Args memory);

    function proportion(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice
    ) external pure returns (uint256);

    function amountOfTicksBetween(
        uint256 lower,
        uint256 upper
    ) external pure returns (uint256);

    function liquidity(
        Pricing.Args memory args
    ) external pure returns (uint256);

    function bidLiquidity(
        Pricing.Args memory args
    ) external pure returns (uint256);

    function askLiquidity(
        Pricing.Args memory args
    ) external pure returns (uint256);

    function maxTradeSize(
        Pricing.Args memory args
    ) external pure returns (uint256);

    function price(
        Pricing.Args memory args,
        uint256 tradeSize
    ) external view returns (uint256);

    function nextPrice(
        Pricing.Args memory args,
        uint256 tradeSize
    ) external view returns (uint256);

    // TODO : Move to PositionMock
    function keyHash(Position.Key memory self) external pure returns (bytes32);

    function opposite(
        Position.OrderType orderType
    ) external pure returns (Position.OrderType);

    function isLeft(Position.OrderType orderType) external pure returns (bool);

    function isRight(Position.OrderType orderType) external pure returns (bool);

    function proportion(
        Position.Key memory self,
        uint256 price
    ) external pure returns (uint256);

    function pieceWiseLinear(
        Position.Key memory self,
        uint256 price
    ) external pure returns (uint256);

    function pieceWiseQuadratic(
        Position.Key memory self,
        uint256 price
    ) external view returns (uint256);
}
