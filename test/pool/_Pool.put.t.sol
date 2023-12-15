// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IPoolMock} from "./mock/IPoolMock.sol";

import {PoolTest} from "./_Pool.t.sol";

contract PoolPutTest is PoolTest {
    function setUp() public override {
        super.setUp();

        isCallTest = false;
        poolKey.isCallPool = false;
        pool = IPoolMock(factory.deployPool(poolKey));
    }
}
