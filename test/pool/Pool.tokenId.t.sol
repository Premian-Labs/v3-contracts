// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {Position} from "contracts/libraries/Position.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTokenIdTest is DeployTest {
    function test_formatTokenId_ReturnExpectedValue() public {
        address _operator = 0x1000000000000000000000000000000000000001;
        uint256 tokenId = pool.formatTokenId(_operator, ud(0.001e18), ud(1e18), Position.OrderType.LC);

        uint256 minTickDistance = 0.001e18;

        uint256 version = tokenId >> 252;
        uint256 orderType = (tokenId >> 180) & 0xF; // 4 bits mask
        address operator = address(uint160(tokenId >> 20));
        uint256 upper = ((tokenId >> 10) & 0x3FF) * minTickDistance; // 10 bits mask
        uint256 lower = (tokenId & 0x3FF) * minTickDistance; // 10 bits mask

        assertEq(version, 1);
        assertEq(orderType, uint256(Position.OrderType.LC));
        assertEq(operator, _operator);
        assertEq(lower, ud(0.001e18));
        assertEq(upper, ud(1e18));
    }

    function test_parseTokenId_ReturnExpectedValue() public {
        uint256 tokenId = 0x10000000000000000021000000000000000000000000000000000000001fa001;

        (uint8 version, address operator, UD60x18 lower, UD60x18 upper, Position.OrderType orderType) = pool
            .parseTokenId(tokenId);

        assertEq(version, 1);
        assertEq(operator, 0x1000000000000000000000000000000000000001);
        assertEq(lower, ud(0.001e18));
        assertEq(upper, ud(1e18));
        assertEq(uint256(orderType), uint256(Position.OrderType.LC));
    }
}
