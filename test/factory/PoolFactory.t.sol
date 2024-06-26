// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {IPool} from "contracts/pool/IPool.sol";

import {Base_Test} from "../Base.t.sol";

abstract contract PoolFactory_Integration_Shared_Test is Base_Test {
    // Variables
    IPoolFactory.PoolKey internal poolKey;
    uint256 internal maturity = 1_682_668_800;

    function setUp() public virtual override {
        super.setUp();

        // Approve V3 Core to spend assets from the users
        approve();

        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: ud(1000 ether),
            maturity: maturity,
            isCallPool: true
        });

        changePrank({msgSender: users.lp});
    }

    function getStartTimestamp() internal virtual override returns (uint256) {
        return 1_679_758_940;
    }

    // deployPool

    function test_deployPool_DeployPool() public {
        address pool = factory.deployPool(poolKey);
        (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint256 maturity_,
            bool isCallPool
        ) = IPool(pool).getPoolSettings();

        assertEq(base, poolKey.base);
        assertEq(quote, poolKey.quote);
        assertEq(oracleAdapter, poolKey.oracleAdapter);
        assertEq(strike, poolKey.strike);
        assertEq(maturity_, poolKey.maturity);
        assertEq(isCallPool, poolKey.isCallPool);
    }

    function test_deployPool_FullRefund() public {
        maturity = (block.timestamp - (block.timestamp % 24 hours)) + 32 hours; // 8AM UTC of the following day
        vm.warp(maturity - 1 hours);

        poolKey.strike = ud(2000 ether);
        poolKey.maturity = maturity + 24 hours;

        uint256 fee = factory.initializationFee(poolKey).unwrap();

        assertEq(fee, 0);
        assertEq(address(factory).balance, 0);

        uint256 lpBalanceBefore = users.lp.balance;
        factory.deployPool{value: 1 ether}(poolKey);

        assertEq(users.lp.balance, lpBalanceBefore);
        assertEq(FEE_RECEIVER.balance, 0);
        assertEq(address(factory).balance, 0);
    }

    function test_deployPool_RevertIf_BaseAndQuoteEqual() public {
        vm.expectRevert(IPoolFactory.PoolFactory__IdenticalAddresses.selector);

        poolKey.base = poolKey.quote;
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_QuoteZeroAddress() public {
        poolKey.quote = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_BaseZeroAddress() public {
        poolKey.base = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_OracleAddress() public {
        poolKey.oracleAdapter = address(0);

        vm.expectRevert(IPoolFactory.PoolFactory__ZeroAddress.selector);
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_StrikeIsZero() public {
        poolKey.strike = ud(0);

        vm.expectRevert(IPoolFactory.PoolFactory__OptionStrikeEqualsZero.selector);
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_AlreadyDeployed() public {
        address poolAddress = factory.deployPool(poolKey);

        vm.expectRevert(abi.encodeWithSelector(IPoolFactory.PoolFactory__PoolAlreadyDeployed.selector, poolAddress));
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_PriceNotWithinStrikeInterval() public {
        uint256[4] memory strike = [uint256(99999 ether), uint256(1050 ether), uint256(961 ether), uint256(11.1 ether)];
        uint256[4] memory interval = [uint256(1000 ether), uint256(100 ether), uint256(10 ether), uint256(1 ether)];

        for (uint256 i; i < strike.length; i++) {
            poolKey.strike = ud(strike[i]);

            vm.expectRevert(
                abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionStrikeInvalid.selector, strike[i], interval[i])
            );

            factory.deployPool(poolKey);
        }
    }

    function test_deployPool_RevertIf_MaturityExpired() public {
        poolKey.maturity = 1679758930;

        vm.expectRevert(abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionExpired.selector, poolKey.maturity));
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_MaturityNot8UTC() public {
        poolKey.maturity = 1679768950;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNot8UTC.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);

        poolKey.maturity = 1688572800;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNot8UTC.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);

        poolKey.maturity = 1688601600;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNot8UTC.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_MaturityWeeklyNotFriday() public {
        poolKey.maturity = 1680163200;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNotFriday.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_MaturityMonthlyNotLastFriday() public {
        poolKey.maturity = 1683878400;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityNotLastFriday.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);
    }

    function test_deployPool_RevertIf_MaturityExceedsOneYear() public {
        poolKey.maturity = 1714118400;

        vm.expectRevert(
            abi.encodeWithSelector(IPoolFactory.PoolFactory__OptionMaturityExceedsMax.selector, poolKey.maturity)
        );
        factory.deployPool(poolKey);
    }

    // getPoolAddress

    function test_getPoolAddress_ReturnIsDeployedFalse() public {
        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);

        assertNotEq(pool, address(0));
        assertFalse(isDeployed);
    }

    function test_getPoolAddress_ReturnIsDeployedTrue() public {
        address poolAddress = factory.deployPool(poolKey);

        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);
        assertEq(pool, poolAddress);
        assertTrue(isDeployed);
    }
}

contract PoolFactory_Call_Integration_Test is PoolFactory_Integration_Shared_Test {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = true;
    }
}

contract PoolFactory_Put_Integration_Test is PoolFactory_Integration_Shared_Test {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = false;
    }
}
