// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {IPool} from "contracts/pool/IPool.sol";

import {Integration_Test} from "../Integration.t.sol";

abstract contract PoolFactory_Integration_Shared_Test is Integration_Test {
    IPoolFactory.PoolKey internal poolKey;
    uint256 internal maturity = 1682668800;

    function setUp() public override {
        Integration_Test.setUp();

        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });

        vm.warp(1679758940);
    }
}
