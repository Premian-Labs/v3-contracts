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
}
