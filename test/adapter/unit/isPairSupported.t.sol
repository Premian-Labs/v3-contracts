// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";

import {ChainlinkAdapter_PathCases_Shared_Test} from "../shared/pathCases.t.sol";

contract ChainlinkAdapter_IsPairSupported_Unit_Concrete_Test is ChainlinkAdapter_PathCases_Shared_Test {
    function test_isPairSupported_ReturnTrue_IfPairCachedAndPathExists() public givenPaths {
        (bool isCached, bool hasPath) = adapter.isPairSupported(p.tokenIn, p.tokenOut);
        assertTrue(isCached);
        assertTrue(hasPath);
    }

    function test_isPairSupported_ReturnFalse_IfPairNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPathDoesNotExist() public {
        (, bool hasPath) = adapter.isPairSupported(WETH, WBTC);
        assertTrue(hasPath);
    }

    function test_isPairSupported_RevertIf_TokensAreSame() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, CRV, CRV));
        adapter.isPairSupported(CRV, CRV);
    }

    function test_isPairSupported_RevertIf_ZeroAddress() public {
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.isPairSupported(address(0), DAI);

        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.isPairSupported(CRV, address(0));
    }
}
