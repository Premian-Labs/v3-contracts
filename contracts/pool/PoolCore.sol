// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";
import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address exchangeHelper,
        address wrappedNativeToken
    ) PoolInternal(exchangeHelper, wrappedNativeToken) {}

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
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 slippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _deposit(p, belowLower, belowUpper, size, slippage);
    }

    function swapAndDeposit(
        SwapArgs memory s,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 slippage
    ) external payable {
        // ToDo : Add orderType check ?

        PoolStorage.Layout storage l = PoolStorage.layout();

        address tokenOut = l.getPoolToken();
        uint256 creditAmount = _swapForPoolTokens(s, tokenOut);

        // ToDo : Finish to implement

        _deposit(p, belowLower, belowUpper, size, slippage);
    }

    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 slippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _withdraw(p, size, slippage);
    }

    function trade(uint256 size, bool isBuy) external returns (uint256) {
        return _trade(msg.sender, size, isBuy);
    }

    function swapAndTrade(
        SwapArgs memory s,
        uint256 size,
        bool isBuy
    ) external payable returns (uint256) {
        // ToDo : Implement
    }

    function tradeAndSwap(
        SwapArgs memory s,
        uint256 size,
        bool isBuy
    ) external {
        // ToDo : Implement
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

    function getNearestTickBelow(
        uint256 price
    ) external view returns (uint256) {
        return _getNearestTickBelow(price);
    }
}
