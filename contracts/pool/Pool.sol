// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";

contract Pool is PoolInternal {
    function getQuote(
        uint256 size,
        Position.Side tradeSide
    ) external view returns (uint256) {
        return _getQuote(size, tradeSide);
    }

    function claim() external {
        _claim();
    }

    function deposit(
        Position.Key memory p,
        Position.Side side,
        uint256 collateral,
        uint256 contracts
    ) external {
        _deposit(p, side, collateral, contracts);
    }

    function withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 contracts
    ) external {
        _withdraw(p, collateral, contracts);
    }

    function trade(
        address owner,
        address operator,
        Position.Side tradeSide,
        uint256 size
    ) external returns (uint256) {
        return _trade(owner, operator, tradeSide, size);
    }

    function annihilate(uint256 size) external {
        _annihilate(msg.sender, size);
    }

    function exercise() external returns (uint256) {
        return _exercise(msg.sender);
    }

    function settle() external returns (uint256) {
        return _settle(msg.sender);
    }

    function settlePosition(Position.Key memory p) external returns (uint256) {
        return _settlePosition(p);
    }
}
