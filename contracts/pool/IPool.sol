// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {Position} from "../libraries/Position.sol";

interface IPool is IPoolBase, IPoolIO {
    function getQuote(uint256 size, bool isBuy) external view returns (uint256);

    function claim(Position.Key memory p) external;

    function deposit(
        Position.Key memory p,
        bool isBuy,
        uint256 collateral,
        uint256 contracts
    ) external;

    function withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 contracts
    ) external;

    function trade(uint256 size, bool isBuy) external returns (uint256);

    function annihilate(uint256 size) external;

    function exercise() external returns (uint256);

    function settle() external returns (uint256);

    function settlePosition(Position.Key memory p) external returns (uint256);
}
