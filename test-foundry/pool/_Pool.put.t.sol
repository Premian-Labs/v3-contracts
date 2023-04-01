// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {IPool} from "contracts/pool/IPool.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {DeployTest} from "../Deploy.t.sol";
import {PoolTest} from "./_Pool.t.sol";

contract PoolPutTest is PoolTest {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = false;
        pool = IPool(factory.deployPool{value: 1 ether}(poolKey));
    }
}
