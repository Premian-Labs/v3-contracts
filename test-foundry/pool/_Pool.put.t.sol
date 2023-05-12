// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {PoolTest} from "./_Pool.t.sol";

contract PoolPutTest is PoolTest {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = false;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
    }
}
