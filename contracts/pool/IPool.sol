// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolIO} from "./IPoolIO.sol";
import {Position} from "../libraries/Position.sol";

interface IPool is IPoolBase, IPoolIO {
    function getQuote(uint256 size, Position.Side tradeSide)
        external
        view
        returns (uint256);

    function claim() external;

    function deposit(
        Position.Key memory p,
        Position.Liquidity memory liqUpdate,
        uint256 left,
        uint256 right
    ) external;

    function withdraw(
        Position.Key memory p,
        Position.Liquidity memory liqUpdate
    ) external;

    function trade(
        address owner,
        address operator,
        Position.Side tradeSide,
        uint256 size
    ) external returns (uint256);

    function annihilate(uint256 amount) external;

    function exercise(address owner, address operator)
        external
        returns (uint256);

    function settle(address owner, address operator) external returns (uint256);

    function settlePosition(Position.Key memory p) external returns (uint256);
}
