// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";

import {ChainlinkAdapter_PathCases_Shared_Test} from "../shared/pathCases.t.sol";

contract ChainlinkAdapter_PricingPath_Unit_Concrete_Test is ChainlinkAdapter_PathCases_Shared_Test {
    function test_pricingPath_ReturnPathForPair_New() public givenPaths {
        IChainlinkAdapter.PricingPath path1 = adapter.pricingPath(p.tokenIn, p.tokenOut);
        IChainlinkAdapter.PricingPath path2 = adapter.pricingPath(p.tokenOut, p.tokenIn);

        assertEq(uint256(path1), uint256(p.path));
        assertEq(uint256(path2), uint256(p.path));
    }
}
