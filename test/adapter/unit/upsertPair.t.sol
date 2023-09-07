// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_UpsertPair_Unit_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function test_upsertPair_ShouldNotRevert_IfCalledMultipleTime_ForSamePair() public {
        adapter.upsertPair(WETH, DAI);
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertTrue(isCached);

        adapter.upsertPair(WETH, DAI);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, address(1), WETH)
        );
        adapter.upsertPair(address(1), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, WBTC, address(1))
        );
        adapter.upsertPair(WBTC, address(1));
    }

    function test_upsertPair_RevertIf_TokensAreSame() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, CRV, CRV));
        adapter.upsertPair(CRV, CRV);
    }

    function test_upsertPair_RevertIf_ZeroAddress() public {
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.upsertPair(address(0), DAI);

        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.upsertPair(CRV, address(0));
    }
}
