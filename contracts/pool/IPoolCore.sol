// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolInternal} from "./IPoolInternal.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolCore {
    function getQuote(uint256 size, bool isBuy) external view returns (uint256);

    function claim(Position.Key memory p) external;

    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external;

    function swapAndDeposit(
        IPoolInternal.SwapArgs memory s,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper
    ) external payable;

    function withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external;

    function trade(uint256 size, bool isBuy) external returns (uint256);

    function swapAndTrade(
        IPoolInternal.SwapArgs memory s,
        uint256 size,
        bool isBuy
    ) external payable returns (uint256);

    function tradeAndSwap(
        IPoolInternal.SwapArgs memory s,
        uint256 size,
        bool isBuy
    ) external;

    function annihilate(uint256 size) external;

    function exercise() external returns (uint256);

    function settle() external returns (uint256);

    function settlePosition(Position.Key memory p) external returns (uint256);

    function getNearestTickBelow(uint256 price) external view returns (uint256);
}
