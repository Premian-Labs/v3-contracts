// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Position} from "../../libraries/Position.sol";

contract PositionMock {
    function keyHash(Position.Key memory self) external pure returns (bytes32) {
        return Position.keyHash(self);
    }

    function isShort(
        Position.OrderType orderType
    ) external pure returns (bool) {
        return Position.isShort(orderType);
    }

    function isLong(Position.OrderType orderType) external pure returns (bool) {
        return Position.isLong(orderType);
    }

    function pieceWiseLinear(
        Position.Key memory self,
        uint256 price
    ) external pure returns (uint256) {
        return Position.pieceWiseLinear(self, price);
    }

    function pieceWiseQuadratic(
        Position.Key memory self,
        uint256 price
    ) external pure returns (uint256) {
        return Position.pieceWiseQuadratic(self, price);
    }

    function collateralToContracts(
        uint256 _collateral,
        uint256 strike,
        bool isCall
    ) external pure returns (uint256) {
        return Position.collateralToContracts(_collateral, strike, isCall);
    }

    function contractsToCollateral(
        uint256 _collateral,
        uint256 strike,
        bool isCall
    ) external pure returns (uint256) {
        return Position.contractsToCollateral(_collateral, strike, isCall);
    }

    function liquidityPerTick(
        Position.Key memory self,
        uint256 size
    ) external pure returns (uint256) {
        return Position.liquidityPerTick(self, size);
    }

    function bid(
        Position.Key memory self,
        uint256 size,
        uint256 price
    ) external pure returns (uint256) {
        return Position.bid(self, size, price);
    }

}
