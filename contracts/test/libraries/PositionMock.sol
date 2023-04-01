// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {Position} from "../../libraries/Position.sol";

contract PositionMock {
    function keyHash(
        Position.KeyInternal memory self
    ) external pure returns (bytes32) {
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
        Position.KeyInternal memory self,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.pieceWiseLinear(self, price);
    }

    function pieceWiseQuadratic(
        Position.KeyInternal memory self,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.pieceWiseQuadratic(self, price);
    }

    function collateralToContracts(
        UD60x18 _collateral,
        UD60x18 strike,
        bool isCall
    ) external pure returns (UD60x18) {
        return Position.collateralToContracts(_collateral, strike, isCall);
    }

    function contractsToCollateral(
        UD60x18 _collateral,
        UD60x18 strike,
        bool isCall
    ) external pure returns (UD60x18) {
        return Position.contractsToCollateral(_collateral, strike, isCall);
    }

    function liquidityPerTick(
        Position.KeyInternal memory self,
        UD60x18 size
    ) external pure returns (UD60x18) {
        return Position.liquidityPerTick(self, size);
    }

    function bid(
        Position.KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.bid(self, size, price);
    }

    function collateral(
        Position.KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.collateral(self, size, price);
    }

    function contracts(
        Position.KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.contracts(self, size, price);
    }

    function long(
        Position.KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.long(self, size, price);
    }

    function short(
        Position.KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) external pure returns (UD60x18) {
        return Position.short(self, size, price);
    }

    function calculatePositionUpdate(
        Position.KeyInternal memory self,
        UD60x18 currentBalance,
        SD59x18 amount,
        UD60x18 price
    ) external pure returns (Position.Delta memory delta) {
        return
            Position.calculatePositionUpdate(
                self,
                currentBalance,
                amount,
                price
            );
    }
}
