// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {Position} from "../libraries/Position.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

interface IPoolCore is IPoolInternal {
    function getQuote(uint256 size, bool isBuy) external view returns (uint256);

    function claim(Position.Key memory p) external;

    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 slippage,
        bool isBid
    ) external;

    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 slippage
    ) external;

    function trade(uint256 size, bool isBuy) external returns (uint256);

    function annihilate(uint256 size) external;

    function exercise() external returns (uint256);

    function settle() external returns (uint256);

    function settlePosition(Position.Key memory p) external returns (uint256);

    function getNearestTicksBelow(
        uint256 lower,
        uint256 upper
    )
        external
        view
        returns (uint256 nearestBelowLower, uint256 nearestBelowUpper);
}
