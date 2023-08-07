// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSettlementPriceTest is DeployTest {
    function test_tryCacheSettlementPrice_Success() public {
        vm.warp(poolKey.maturity);
        pool.tryCacheSettlementPrice();
        assertEq(pool.getSettlementPrice(), settlementPrice);
    }

    function test_tryCacheSettlementPrice_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.tryCacheSettlementPrice();
    }

    function test_tryCacheSettlementPrice_RevertIf_SettlementPriceAlreadyCached() public {
        test_tryCacheSettlementPrice_Success();
        vm.expectRevert(IPoolInternal.Pool__SettlementPriceAlreadyCached.selector);
        pool.tryCacheSettlementPrice();
    }
}
