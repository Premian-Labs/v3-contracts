// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter} from "contracts/adapter/chainlink/IChainlinkAdapter.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_BatchRegisterFeedMappings_Unit_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function test_batchRegisterFeedMappings_RevertIf_TokensAreSame() public {
        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(EUL, EUL, address(1));

        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, EUL, EUL));
        adapter.batchRegisterFeedMappings(data);
    }

    function test_batchRegisterFeedMappings_RevertIf_ZeroAddress() public {
        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);

        data[0] = IFeedRegistry.FeedMappingArgs(address(0), DAI, address(1));
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);

        data[0] = IFeedRegistry.FeedMappingArgs(EUL, address(0), address(1));
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.batchRegisterFeedMappings(data);
    }

    function test_batchRegisterFeedMappings_RevertIf_InvalidDenomination() public {
        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(WETH, CRV, address(1));
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__InvalidDenomination.selector, CRV));
        adapter.batchRegisterFeedMappings(data);
    }

    function test_batchRegisterFeedMappings_RevertIf_NotOwner() public {
        changePrank({msgSender: users.alice});

        IFeedRegistry.FeedMappingArgs[] memory data = new IFeedRegistry.FeedMappingArgs[](1);
        data[0] = IFeedRegistry.FeedMappingArgs(DAI, CHAINLINK_USD, address(0));
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        adapter.batchRegisterFeedMappings(data);
    }
}
