// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";

contract Pool is PoolInternal {
    function getQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256) {
        return _getQuote(size, isBuy);
    }

    function claim(Position.Key memory p) external {
        _claim(p);
    }

    function deposit(
        Position.Key memory p,
        Position.OrderType orderType,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external {
        _deposit(p, orderType, collateral, longs, shorts);
    }

    function withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external {
        _withdraw(p, collateral, longs, shorts);
    }

    function trade(uint256 size, bool isBuy) external returns (uint256) {
        return _trade(msg.sender, size, isBuy);
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
