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

    fallback() external payable {}

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

    function test_PoolAddress0IfNotDeployed() public {
        assertEq(factory.getPoolAddress(poolKey), address(0));
    }

    function test_RevertIfBaseAndQuoteEqual() public {
        vm.expectRevert(IPoolFactory.PoolFactory__IdenticalAddresses.selector);

        poolKey.base = poolKey.quote;
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_deployPool() public {
        factory.deployPool{value: 1 ether}(poolKey);
    }

    function test_RevertIfDeployed() public {
        factory.deployPool{value: 1 ether}(poolKey);

        vm.expectRevert(IPoolFactory.PoolFactory__PoolAlreadyDeployed.selector);
        factory.deployPool{value: 1 ether}(poolKey);
    }
}
