// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {IPool} from "contracts/pool/IPool.sol";

import {DeployTest} from "../Deploy.t.sol";

contract PoolFactoryTest is DeployTest {
    function setUp() public override {
        super.setUp();
        vm.warp(1679758940);
    }

    function test_getPoolAddress_ReturnIsDeployedFalse() public {
        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);

        assert(pool != address(0));
        assertFalse(isDeployed);
    }

    function test_getPoolAddress_ReturnIsDeployedTrue() public {
        address poolAddress = factory.deployPool{value: 1 ether}(poolKey);

        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);
        assertEq(pool, poolAddress);
        assertTrue(isDeployed);
    }

    function test_deployPool_DeployPool() public {
        address pool = factory.deployPool{value: 1 ether}(poolKey);

        (address base, address quote, address oracleAdapter, UD60x18 strike, uint256 maturity, bool isCallPool) = IPool(
            pool
        ).getPoolSettings();

        assertEq(base, poolKey.base);
        assertEq(quote, poolKey.quote);
        assertEq(oracleAdapter, poolKey.oracleAdapter);
        assertEq(strike, poolKey.strike);
        assertEq(maturity, poolKey.maturity);
        assertEq(isCallPool, poolKey.isCallPool);
    }

    function test_deployPool_RevertIf_BaseAndQuoteEqual() public {
        vm.expectRevert(IPoolFactory.PoolFactory__IdenticalAddresses.selector);

        poolKey.base = poolKey.quote;
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_QuoteZeroAddress() public {
        poolKey.quote = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_BaseZeroAddress() public {
        poolKey.base = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_OracleAddress() public {
        poolKey.oracleAdapter = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_StrikeIsZero() public {
        poolKey.strike = ud(0);

        vm.expectRevert(IPoolFactory.PoolFactory__OptionStrikeEqualsZero.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_AlreadyDeployed() public {
        address poolAddress = factory.deployPool{value: 1 ether}(poolKey);

        vm.expectRevert(abi.encodeWithSelector(IPoolFactory.PoolFactory__PoolAlreadyDeployed.selector, poolAddress));
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_PriceNotWithinStrikeInterval() public {
        uint256[4] memory strike = [uint256(99990 ether), uint256(1050 ether), uint256(950 ether), uint256(11 ether)];

        uint256 strikeInterval = 100 ether;

        for (uint256 i; i < strike.length; i++) {
            poolKey.strike = ud(strike[i]);

            vm.expectRevert(
                abi.encodeWithSelector(
                    IPoolFactory.PoolFactory__OptionStrikeInvalid.selector,
                    strike[i],
                    strikeInterval
                )
            );

            factory.deployPool{value: 1 ether}(poolKey);
        }
    }

    function test_deployPool_RevertIf_MaturityExpired() public {
        poolKey.maturity = 1679758930;

        vm.expectRevert(abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionExpired.selector, poolKey.maturity));
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityNot8UTC() public {
        poolKey.maturity = 1679768950;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNot8UTC.selector, poolKey.maturity)
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityWeeklyNotFriday() public {
        poolKey.maturity = 1680163200;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNotFriday.selector, poolKey.maturity)
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityMonthlyNotLastFriday() public {
        poolKey.maturity = 1683878400;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNotLastFriday.selector, poolKey.maturity)
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityExceedsOneYear() public {
        poolKey.maturity = 1714118400;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityExceedsMax.selector, poolKey.maturity)
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }
}
