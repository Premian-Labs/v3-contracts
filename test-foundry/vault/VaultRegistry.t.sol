// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";

import {Assertions} from "../Assertions.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IVaultRegistry} from "../../contracts/vault/IVaultRegistry.sol";
import {VaultRegistry} from "../../contracts/vault/VaultRegistry.sol";
import {VaultRegistryStorage} from "../../contracts/vault/VaultRegistryStorage.sol";
import {ProxyUpgradeableOwnable} from "../../contracts/proxy/ProxyUpgradeableOwnable.sol";

contract VaultRegistryHarness is VaultRegistry {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;

    function hasSettings(bytes32 vaultType) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.settings[vaultType].length != 0;
    }
}

contract VaultRegistryTest is Test, Assertions {
    address deployer;
    address user = address(1);
    bytes32 vaultType = keccak256("NewVaultWhoDis");
    VaultRegistry registryImpl;
    ProxyUpgradeableOwnable registry;

    function setUp() public {
        deployer = msg.sender;
        vm.startPrank(deployer);

        // 1. Create registry implementation
        registryImpl = new VaultRegistryHarness();

        // 2. Create registry proxy
        registry = new ProxyUpgradeableOwnable(address(registryImpl));

        vm.stopPrank();
    }

    function test_setup() public {
        assert(address(registry) != address(0));

        assertEq(IVaultRegistry(address(registry)).getNumberOfVaults(), 0);
    }

    function test_addVault() public {
        vm.prank(deployer);
        IVaultRegistry(address(registry)).addVault(
            address(123),
            keccak256("NewVaultWhoDis"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );

        assertEq(IVaultRegistry(address(registry)).getNumberOfVaults(), 1);
    }

    function test_addVault_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        IVaultRegistry(address(registry)).addVault(
            address(123),
            keccak256("NewVaultWhoDis"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );
    }

    function test_removeVault() public {
        vm.prank(deployer);
        IVaultRegistry(address(registry)).addVault(
            address(123),
            keccak256("NewVaultWhoDis"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );

        assertEq(IVaultRegistry(address(registry)).getNumberOfVaults(), 1);

        vm.prank(deployer);
        IVaultRegistry(address(registry)).removeVault(address(123));
        assertEq(IVaultRegistry(address(registry)).getNumberOfVaults(), 0);
    }

    function test_removeVault_revertIf_NotOwner() public {
        vm.prank(deployer);
        IVaultRegistry(address(registry)).addVault(
            address(123),
            keccak256("NewVaultWhoDis"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );

        assertEq(IVaultRegistry(address(registry)).getNumberOfVaults(), 1);

        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        IVaultRegistry(address(registry)).removeVault(address(123));
    }

    function test_updateSettings() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(deployer);
        IVaultRegistry(address(registry)).updateSettings(vaultType, settings);

        assert(VaultRegistryHarness(address(registry)).hasSettings(vaultType));
    }

    function test_updateSettings_revertIf_NotOwner() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        IVaultRegistry(address(registry)).updateSettings(vaultType, settings);

        assert(!VaultRegistryHarness(address(registry)).hasSettings(vaultType));
    }

    function test_getSettings() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(deployer);
        IVaultRegistry(address(registry)).updateSettings(vaultType, settings);

        vm.prank(user);
        settings = VaultRegistryHarness(address(registry)).getSettings(
            vaultType
        );

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
}
