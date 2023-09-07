// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_BatchRegisterFeedMappings_Fork_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function isForkTest() internal virtual override returns (bool) {
        return true;
    }

    function test_batchRegisterFeedMappings_RemoveFeed() public {
        adapter.upsertPair(YFI, DAI);
        adapter.upsertPair(USDC, YFI);

        assertTrue(adapter.pricingPath(YFI, DAI) == IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN);
        assertTrue(adapter.pricingPath(USDC, YFI) == IChainlinkAdapter.PricingPath.TOKEN_USD_TOKEN);

        {
            UD60x18 quote = adapter.getPrice(YFI, DAI);
            assertGt(quote.unwrap(), 0);
        }

        {
            UD60x18 quote = adapter.getPrice(USDC, YFI);
            assertGt(quote.unwrap(), 0);
        }

        {
            (bool isCached, bool hasPath) = adapter.isPairSupported(YFI, DAI);
            assertTrue(isCached);
            assertTrue(hasPath);
        }

        {
            (bool isCached, bool hasPath) = adapter.isPairSupported(USDC, YFI);
            assertTrue(isCached);
            assertTrue(hasPath);
        }

        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(YFI);

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 2);
            assertEq(path[0][0], 0x8a4D74003870064d41D4f84940550911FBfCcF04);
            assertEq(path[1][0], 0x37bC7498f4FF12C19678ee8fE19d713b87F6a9e6);
            assertEq(decimals.length, 2);
            assertEq(decimals[0], 8);
            assertEq(decimals[1], 8);
        }

        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(YFI, CHAINLINK_USD, address(0));
        adapter.batchRegisterFeedMappings(data);

        vm.expectRevert();
        adapter.upsertPair(YFI, DAI);

        vm.expectRevert();
        adapter.upsertPair(USDC, YFI);

        assertTrue(adapter.pricingPath(YFI, DAI) == IChainlinkAdapter.PricingPath.NONE);
        assertTrue(adapter.pricingPath(USDC, YFI) == IChainlinkAdapter.PricingPath.NONE);

        vm.expectRevert();
        adapter.getPrice(YFI, DAI);

        vm.expectRevert();
        adapter.getPrice(USDC, YFI);

        {
            (bool isCached, bool hasPath) = adapter.isPairSupported(YFI, DAI);
            assertFalse(isCached);
            assertFalse(hasPath);
        }

        {
            (bool isCached, bool hasPath) = adapter.isPairSupported(USDC, YFI);
            assertFalse(isCached);
            assertFalse(hasPath);
        }

        {
            (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
                .describePricingPath(YFI);

            assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.Chainlink));
            assertEq(path.length, 0);
            assertEq(decimals.length, 0);
        }
    }
}
