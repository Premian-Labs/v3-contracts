// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_DescribePricingPath_Fork_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function isForkTest() internal virtual override returns (bool) {
        return true;
    }

    function test_describePricingPath_Success() public {
        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(address(1));

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 0);
            assertEq(decimals.length, 0);
        }

        //

        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(WETH);

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 1);
            assertEq(path[0][0], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
            assertEq(decimals.length, 1);
            assertEq(decimals[0], 18);
        }

        //

        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(DAI);

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 1);
            assertEq(path[0][0], 0x158228e08C52F3e2211Ccbc8ec275FA93f6033FC);
            assertEq(decimals.length, 1);
            assertEq(decimals[0], 18);
        }

        //

        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(ENS);

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 2);
            assertEq(path[0][0], 0x780f1bD91a5a22Ede36d4B2b2c0EcCB9b1726a28);
            assertEq(path[1][0], 0x37bC7498f4FF12C19678ee8fE19d713b87F6a9e6);
            assertEq(decimals.length, 2);
            assertEq(decimals[0], 8);
            assertEq(decimals[0], 8);
        }
    }
}
