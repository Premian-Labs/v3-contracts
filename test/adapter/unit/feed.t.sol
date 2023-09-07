// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_Feed_Unit_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function test_feed_ReturnFeed() public {
        IFeedRegistry.FeedMappingArgs[] memory _feeds = feeds();

        for (uint256 i = 0; i < _feeds.length; i++) {
            assertEq(adapter.feed(_feeds[i].token, _feeds[i].denomination), _feeds[i].feed);
        }
    }

    function test_feed_ReturnZeroAddress_IfFeedDoesNotExist() public {
        assertEq(adapter.feed(EUL, DAI), address(0));
    }
}
