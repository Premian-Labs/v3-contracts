// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";
import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal {
    /// @inheritdoc IPoolCore
    function getQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256) {
        return _getQuote(size, isBuy);
    }

    /// @inheritdoc IPoolCore
    function claim(Position.Key memory p) external {
        _claim(p);
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 slippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _deposit(p, belowLower, belowUpper, size, slippage);
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 slippage,
        bool isBidIfStrandedMarketPrice
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _deposit(p, belowLower, belowUpper, size, slippage, isBid);
    }

    /// @inheritdoc IPoolCore
    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 slippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _withdraw(p, size, slippage);
    }

    /// @inheritdoc IPoolCore
    function trade(uint256 size, bool isBuy) external returns (uint256) {
        return _trade(msg.sender, size, isBuy);
    }

    /// @inheritdoc IPoolCore
    function annihilate(uint256 size) external {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise() external returns (uint256) {
        return _exercise(msg.sender);
    }

    /// @inheritdoc IPoolCore
    function settle() external returns (uint256) {
        return _settle(msg.sender);
    }

    /// @inheritdoc IPoolCore
    function settlePosition(Position.Key memory p) external returns (uint256) {
        return _settlePosition(p);
    }

    /// @inheritdoc IPoolCore
    function getNearestTicksBelow(
        uint256 lower,
        uint256 upper
    )
        external
        view
        returns (uint256 nearestBelowLower, uint256 nearestBelowUpper)
    {
        return _getNearestTicksBelow(lower, upper);
    }
}
