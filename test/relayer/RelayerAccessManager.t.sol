// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {IRelayerAccessManager} from "contracts/relayer/IRelayerAccessManager.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {RelayerAccessManagerMock} from "contracts/test/relayer/RelayerAccessManagerMock.sol";

import {Base_Test} from "../Base.t.sol";

contract RelayerAccessManager_Unit_Concrete_Test is Base_Test {
    // Test contracts
    RelayerAccessManagerMock internal relayerAccessManager;

    // Variables
    address internal relayer;
    address internal alice;
    address internal bob;
    address internal charles;

    function setUp() public override {
        super.setUp();

        relayer = vm.addr(1);
        alice = vm.addr(2);
        bob = vm.addr(3);
        charles = vm.addr(4);

        address[] memory relayers = new address[](1);
        relayers[0] = relayer;
        relayerAccessManager.addWhitelistedRelayers(relayers);
    }

    function deploy() internal virtual override {
        RelayerAccessManagerMock implementation = new RelayerAccessManagerMock();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        relayerAccessManager = RelayerAccessManagerMock(address(proxy));
    }

    function _addWhitelistedRelayers() internal {
        address[] memory relayers = new address[](3);
        relayers[0] = alice;
        relayers[1] = bob;
        relayers[2] = charles;
        relayerAccessManager.addWhitelistedRelayers(relayers);
    }

    function test_addWhitelistedRelayers_Success() public {
        _addWhitelistedRelayers();

        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 4);
            assertEq(relayers[0], relayer);
            assertEq(relayers[1], alice);
            assertEq(relayers[2], bob);
            assertEq(relayers[3], charles);
        }
    }

    function test_addWhitelistedRelayers_RevertIf_NotOwner() public {
        address[] memory relayers = new address[](1);
        relayers[0] = alice;

        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);

        changePrank(bob);
        relayerAccessManager.addWhitelistedRelayers(relayers);
    }

    function test_removeWhitelistedRelayers_Success() public {
        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 1);
            assertEq(relayers[0], relayer);
            relayerAccessManager.removeWhitelistedRelayers(relayers);
        }

        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 0);
        }

        _addWhitelistedRelayers();

        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 3);
            assertEq(relayers[0], alice);
            assertEq(relayers[1], bob);
            assertEq(relayers[2], charles);
        }

        {
            address[] memory relayers = new address[](2);
            relayers[0] = charles;
            relayers[1] = alice;
            relayerAccessManager.removeWhitelistedRelayers(relayers);
        }

        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 1);
            assertEq(relayers[0], bob);
            relayerAccessManager.removeWhitelistedRelayers(relayers);
        }

        {
            address[] memory relayers = relayerAccessManager.getWhitelistedRelayers();
            assertEq(relayers.length, 0);
        }
    }

    function test_removeWhitelistedRelayers_RevertIf_NotOwner() public {
        address[] memory relayers = new address[](1);
        relayers[0] = alice;

        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);

        changePrank(bob);
        relayerAccessManager.removeWhitelistedRelayers(relayers);
    }

    function test___revertIfNotWhitelistedRelayer_IsWhitelistedRelayer() public {
        address[] memory relayers = new address[](1);
        relayers[0] = alice;
        relayerAccessManager.addWhitelistedRelayers(relayers);
        relayerAccessManager.__revertIfNotWhitelistedRelayer(relayer);
    }

    function test___revertIfNotWhitelistedRelayer_RevertIf_NotWhitelistedRelayer() public {
        address notRelayer = vm.addr(99);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRelayerAccessManager.RelayerAccessManager__NotWhitelistedRelayer.selector,
                notRelayer
            )
        );

        relayerAccessManager.__revertIfNotWhitelistedRelayer(notRelayer);
    }
}
