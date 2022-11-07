// SPDX-License-Identifier: UNLICENSED



// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";

contract Pool is PoolInternal {
    function getQuote(uint256 size, Position.Side tradeSide)
        external
        view
        returns (uint256)
    {
        return _getQuote(size, tradeSide);
    }

    function claim() external {
        _claim();
    }

    function deposit(
        Position.Key memory p,
        Position.Side side,
        uint256 collateral,
        uint256 contracts,
        uint256 left,
        uint256 right
    ) external {
        _deposit(p, side, collateral, contracts, left, right);
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

    function annihilate(uint256 amount) external {
        _annihilate(amount);
    }

    function exercise(address owner, address operator)
        external
        returns (uint256)
    {
        return _exercise(owner, operator);
    }

    function settle(address owner, address operator)
        external
        returns (uint256)
    {
        return _settle(owner, operator);
    }

    function settlePosition(Position.Key memory p) external returns (uint256) {
        return _settlePosition(p);
    }
}
