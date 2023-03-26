// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/Test.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {OracleAdapterMock} from "contracts/test/oracle/OracleAdapterMock.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {PoolFactory} from "contracts/factory/PoolFactory.sol";
import {PoolFactoryProxy} from "contracts/factory/PoolFactoryProxy.sol";
import {Premia} from "contracts/proxy/Premia.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

contract PoolFactoryTest is Test {
    ERC20Mock base;
    ERC20Mock quote;
    OracleAdapterMock oracleAdapter;
    IPoolFactory.PoolKey poolKey;
    PoolFactory factory;
    Premia diamond;

    receive() external payable {}

    function setUp() public {
        vm.warp(1679758940);

        base = new ERC20Mock("WETH", 18);
        quote = new ERC20Mock("USDC", 6);
        oracleAdapter = new OracleAdapterMock(
            address(base),
            address(quote),
            UD60x18.wrap(1000 ether),
            UD60x18.wrap(1000 ether)
        );
        poolKey = IPoolFactory.PoolKey({
            base: address(base),
            quote: address(quote),
            oracleAdapter: address(oracleAdapter),
            strike: UD60x18.wrap(1000 ether),
            maturity: 1682668800,
            isCallPool: true
        });

        diamond = new Premia();

        PoolFactory impl = new PoolFactory(
            address(diamond),
            address(oracleAdapter),
            address(base)
        );

        PoolFactoryProxy proxy = new PoolFactoryProxy(
            address(impl),
            UD60x18.wrap(0.1 ether),
            address(0x95222290DD7278Aa3Ddd389Cc1E1d165CC4BAfe5)
        );

        factory = PoolFactory(address(proxy));
    }

    function test_getPoolAddress_ReturnAddress0IfNotDeployed() public {
        assertEq(factory.getPoolAddress(poolKey), address(0));
    }

    function test_getPoolAddress_ReturnPoolAddressIfDeployed() public {
        address poolAddress = factory.deployPool{value: 1 ether}(poolKey);

        assertEq(factory.getPoolAddress(poolKey), poolAddress);
    }

    function test_deployPool_DeployPool() public {
        factory.deployPool{value: 1 ether}(poolKey);
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
