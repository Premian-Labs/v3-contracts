// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {DeployTest} from "./Deploy.t.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";

contract PoolFactoryTest is DeployTest {
    function setUp() public override {
        super.setUp();
    }

    function test_getPoolAddress_ReturnAddress0IfNotDeployed() public {
        assertEq(factory.getPoolAddress(poolKey), address(0));
    }

    function test_getPoolAddress_ReturnPoolAddressIfDeployed() public {
        address poolAddress = factory.deployPool{value: 1 ether}(poolKey);

        assertEq(factory.getPoolAddress(poolKey), poolAddress);
    }

    function test_deployPool_DeployPool() public {
        address pool = factory.deployPool{value: 1 ether}(poolKey);

        (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint64 maturity,
            bool isCallPool
        ) = IPool(pool).getPoolSettings();

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
        poolKey.strike = UD60x18.wrap(0);

        vm.expectRevert(
            IPoolFactory.PoolFactory__OptionStrikeEqualsZero.selector
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_AlreadyDeployed() public {
        factory.deployPool{value: 1 ether}(poolKey);

        vm.expectRevert(IPoolFactory.PoolFactory__PoolAlreadyDeployed.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_PriceNotWithinStrikeInterval() public {
        uint256[4] memory strike = [
            uint256(99990 ether),
            uint256(1050 ether),
            uint256(950 ether),
            uint256(11 ether)
        ];

        for (uint256 i; i < strike.length; i++) {
            poolKey.strike = UD60x18.wrap(strike[i]);

            vm.expectRevert(
                IPoolFactory.PoolFactory__OptionStrikeInvalid.selector
            );

            factory.deployPool{value: 1 ether}(poolKey);
        }
    }

    function test_deployPool_RevertIf_MaturityExpired() public {
        poolKey.maturity = 1679758930;

        vm.expectRevert(IPoolFactory.PoolFactory__OptionExpired.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityNot8UTC() public {
        poolKey.maturity = 1679768950;

        vm.expectRevert(
            IPoolFactory.PoolFactory__OptionMaturityNot8UTC.selector
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityWeeklyNotFriday() public {
        poolKey.maturity = 1680163200;

        vm.expectRevert(
            IPoolFactory.PoolFactory__OptionMaturityNotFriday.selector
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityMonthlyNotLastFriday() public {
        poolKey.maturity = 1683878400;

        vm.expectRevert(
            IPoolFactory.PoolFactory__OptionMaturityNotLastFriday.selector
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool_RevertIf_MaturityExceedsOneYear() public {
        poolKey.maturity = 1714118400;

        vm.expectRevert(
            IPoolFactory.PoolFactory__OptionMaturityExceedsMax.selector
        );
        factory.deployPool{value: 1 ether}(poolKey);
    }
}
