// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";
import {VaultSettings} from "contracts/vault/VaultSettings.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

contract VaultSettingsTest is Test {
    address owner;
    address user = address(1);
    bytes32 vaultType;
    VaultSettings settingsContract;

    function setUp() public {
        vaultType = keccak256("NewVaultWhoDis");
        settingsContract = new VaultSettings();

        owner = settingsContract.owner();

        bytes memory settings = abi.encode(234, "hello", "1) What");

        vm.prank(owner);
        settingsContract.updateSettings(vaultType, settings);
    }

    function testGetSettings() public {
        vm.prank(user);
        bytes memory settings = settingsContract.getSettings(vaultType);

        (uint256 number, string memory word1, string memory word2) = abi.decode(
            settings,
            (uint256, string, string)
        );

        assertEq(number, 234);
        assertEq(word1, "hello");
        assertEq(word2, "1) What");
    }

    function testUpgradeSettingsByOwner() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(owner);
        settingsContract.updateSettings(vaultType, settings);

        settings = settingsContract.getSettings(vaultType);

        (
            string memory word1,
            string memory word2,
            uint256 num1,
            uint256 num2
        ) = abi.decode(settings, (string, string, uint256, uint256));

        assertEq(word1, "1) What");
        assertEq(word2, "2) H");
        assertEq(num1, 9000000000);
        assertEq(num2, 0);
    }

    function testUpgradeSettingsRevertedForNonOwner() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        settingsContract.updateSettings(vaultType, settings);
    }
}
