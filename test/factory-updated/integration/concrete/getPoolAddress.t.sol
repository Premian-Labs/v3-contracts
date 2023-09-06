// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PoolFactory_Integration_Shared_Test} from "../shared/PoolFactory.t.sol";

contract PoolFactory_GetPoolAddress_Concrete_Test is PoolFactory_Integration_Shared_Test {
    function test_getPoolAddress_ReturnIsDeployedFalse() public {
        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);

        assertNotEq(pool, address(0));
        assertFalse(isDeployed);
    }

    function test_getPoolAddress_ReturnIsDeployedTrue() public {
        address poolAddress = factory.deployPool{value: 1 ether}(poolKey);

        (address pool, bool isDeployed) = factory.getPoolAddress(poolKey);
        assertEq(pool, poolAddress);
        assertTrue(isDeployed);
    }
}
