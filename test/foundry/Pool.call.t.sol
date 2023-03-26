// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {DeployTest} from "./Deploy.t.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {PoolTest} from "./Pool.t.sol";

contract PoolCallTest is PoolTest {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = true;
        pool = IPool(factory.deployPool{value: 1 ether}(poolKey));
    }
}
