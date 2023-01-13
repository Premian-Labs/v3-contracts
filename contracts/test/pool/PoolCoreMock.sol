// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Position} from "../../libraries/Position.sol";

import {PoolCore} from "../../pool/PoolCore.sol";
import {PoolStorage} from "../../pool/PoolStorage.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

contract PoolCoreMock is IPoolCoreMock, PoolCore {
    using PoolStorage for PoolStorage.Layout;

    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId) {
        return PoolStorage.formatTokenId(operator, lower, upper, orderType);
    }

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (
            uint8 version,
            address operator,
            uint256 lower,
            uint256 upper,
            Position.OrderType orderType
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }
}
