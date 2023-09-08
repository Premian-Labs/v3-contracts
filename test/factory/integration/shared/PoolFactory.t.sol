// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {IPool} from "contracts/pool/IPool.sol";

import {Integration_Test} from "../Integration.t.sol";

abstract contract PoolFactory_Integration_Shared_Test is Integration_Test {
    IPoolFactory.PoolKey internal poolKey;
    uint256 internal maturity = 1682668800;

    function setUp() public virtual override {
        Integration_Test.setUp();

        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });
    }

    function getStartTimestamp() internal virtual override returns (uint256) {
        return 1_679_758_940;
    }

    modifier givenCallOrPut() {
        emit log("givenCall");

        uint256 snapshot = vm.snapshot();

        poolKey.isCallPool = true;
        _;

        vm.revertTo(snapshot);

        emit log("givenPut");
        poolKey.isCallPool = false;
        _;
    }
}
