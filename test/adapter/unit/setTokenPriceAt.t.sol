// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IChainlinkAdapter, ChainlinkAdapter} from "contracts/adapter/chainlink/ChainlinkAdapter.sol";
import {IRelayerAccessManager} from "contracts/relayer/IRelayerAccessManager.sol";

import {ChainlinkAdapter_Shared_Test} from "../shared/ChainlinkAdapter.t.sol";

contract ChainlinkAdapter_SetTokenPriceAt_Unit_Concrete_Test is ChainlinkAdapter_Shared_Test {
    function setUp() public virtual override {
        ChainlinkAdapter_Shared_Test.setUp();

        changePrank({msgSender: users.relayer});
    }

    function test_setTokenPriceAt_Success() public {
        adapter.setTokenPriceAt(address(1), CHAINLINK_USD, block.timestamp, ONE);
    }

    function test_setTokenPriceAt_RevertIf_TokensAreSame() public {
        vm.expectRevert(abi.encodeWithSelector(IOracleAdapter.OracleAdapter__TokensAreSame.selector, CRV, CRV));
        adapter.setTokenPriceAt(CRV, CRV, block.timestamp, ONE);
    }

    function test_setTokenPriceAt_RevertIf_ZeroAddress() public {
        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.setTokenPriceAt(address(0), DAI, block.timestamp, ONE);

        vm.expectRevert(IOracleAdapter.OracleAdapter__ZeroAddress.selector);
        adapter.setTokenPriceAt(CRV, address(0), block.timestamp, ONE);
    }

    function test_setTokenPriceAt_RevertIf_InvalidDenomination() public {
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkAdapter__InvalidDenomination.selector, CRV));
        adapter.setTokenPriceAt(address(1), CRV, block.timestamp, ONE);
    }

    function test_setTokenPriceAt_RevertIf_NotWhitelistedRelayer() public {
        changePrank({msgSender: users.alice});

        vm.expectRevert(
            abi.encodeWithSelector(
                IRelayerAccessManager.RelayerAccessManager__NotWhitelistedRelayer.selector,
                users.alice
            )
        );
        adapter.setTokenPriceAt(address(1), CHAINLINK_USD, block.timestamp, ONE);
    }
}
