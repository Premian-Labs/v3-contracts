// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IVaultRegistry} from "../../contracts/vault/IVaultRegistry.sol";
import {VaultRegistry} from "../../contracts/vault/VaultRegistry.sol";
import {VaultRegistryStorage} from "../../contracts/vault/VaultRegistryStorage.sol";
import {ProxyUpgradeableOwnable} from "../../contracts/proxy/ProxyUpgradeableOwnable.sol";

contract VaultRegistryHarness is VaultRegistry {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

    function hasSettings(bytes32 vaultType) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.settings[vaultType].length != 0;
    }

    function hasImplementation(bytes32 vaultType) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.implementations[vaultType] != address(0);
    }

    function hasPurgedVaultFromStorage(
        address vaultAddress,
        bytes32 vaultType
    ) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        IVaultRegistry.Vault memory vault = l.vaults[vaultAddress];

        if (vault.vault != address(0)) return false;
        if (l.vaultsByType[vaultType].contains(vaultAddress)) return false;
        if (
            l.vaultsByTradeSide[IVaultRegistry.TradeSide.Buy].contains(
                vaultAddress
            )
        ) return false;
        if (
            l.vaultsByTradeSide[IVaultRegistry.TradeSide.Sell].contains(
                vaultAddress
            )
        ) return false;
        if (
            l.vaultsByTradeSide[IVaultRegistry.TradeSide.Both].contains(
                vaultAddress
            )
        ) return false;
        if (
            l.vaultsByOptionType[IVaultRegistry.OptionType.Call].contains(
                vaultAddress
            )
        ) return false;
        if (
            l.vaultsByOptionType[IVaultRegistry.OptionType.Put].contains(
                vaultAddress
            )
        ) return false;
        if (
            l.vaultsByOptionType[IVaultRegistry.OptionType.Both].contains(
                vaultAddress
            )
        ) return false;

        return true;
    }
}

contract VaultRegistryTest is Test, Assertions {
    // Events
    event VaultAdded(
        address indexed vault,
        bytes32 vaultType,
        IVaultRegistry.TradeSide side,
        IVaultRegistry.OptionType optionType
    );

    event VaultRemoved(address indexed vault);

    // Variables
    address deployer;
    address user = address(1);
    bytes32 vaultType = keccak256("NewVaultWhoDis");
    VaultRegistryHarness registry;

    function setUp() public {
        deployer = msg.sender;
        vm.startPrank(deployer);

        // 1. Create registry implementation
        VaultRegistryHarness impl = new VaultRegistryHarness();

        // 2. Create registry proxy
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(
            address(impl)
        );

        registry = VaultRegistryHarness(address(proxy));

        vm.stopPrank();
    }

    function test_setUp() public {
        assert(address(registry) != address(0));

        assertEq(registry.getNumberOfVaults(), 0);
    }

    function test_getNumberOfVaults() public {
        uint256 n = registry.getNumberOfVaults();
        assertEq(n, 0);

        // Add a vault
        vm.prank(deployer);
        registry.addVault(
            address(10),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        n = registry.getNumberOfVaults();
        assertEq(n, 1);

        // Add another vault
        vm.prank(deployer);
        registry.addVault(
            address(11),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        n = registry.getNumberOfVaults();
        assertEq(n, 2);

        // Remove a vault
        vm.prank(deployer);
        registry.removeVault(address(11));

        n = registry.getNumberOfVaults();
        assertEq(n, 1);
    }

    function test_addVault() public {
        vm.prank(deployer);
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        assertEq(registry.getNumberOfVaults(), 1);
    }

    function test_addVault_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );
    }

    function test_removeVault() public {
        vm.startPrank(deployer);

        // Add vault to registry
        vm.expectEmit(true, true, true, true, address(registry));
        emit VaultAdded(
            address(123),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );

        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        assertEq(registry.getNumberOfVaults(), 1);

        // Remove vault from registry
        registry.removeVault(address(123));
        assertEq(registry.getNumberOfVaults(), 0);
        assert(registry.hasPurgedVaultFromStorage(address(123), vaultType));

        // Remove vault with OptionType.Both from registry
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Both,
            "default"
        );

        registry.removeVault(address(123));
        assertEq(registry.getNumberOfVaults(), 0);
        assert(registry.hasPurgedVaultFromStorage(address(123), vaultType));

        // Remove vault with TradeSide.Both from registry
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        registry.removeVault(address(123));
        assertEq(registry.getNumberOfVaults(), 0);
        assert(registry.hasPurgedVaultFromStorage(address(123), vaultType));

        // Remove vault with OptionType.Both and TradeSide.Both from registry
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Both,
            "default"
        );

        registry.removeVault(address(123));
        assertEq(registry.getNumberOfVaults(), 0);
        assert(registry.hasPurgedVaultFromStorage(address(123), vaultType));
    }

    function test_removeVault_revertIf_NotOwner() public {
        vm.prank(deployer);
        registry.addVault(
            address(123),
            address(2),
            vaultType,
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call,
            "default"
        );

        assertEq(registry.getNumberOfVaults(), 1);

        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        registry.removeVault(address(123));
    }

    function test_updateSettings() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(deployer);
        registry.updateSettings(vaultType, settings);

        assert(registry.hasSettings(vaultType));
    }

    function test_updateSettings_revertIf_NotOwner() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        registry.updateSettings(vaultType, settings);

        assert(!registry.hasSettings(vaultType));
    }

    function test_getSettings() public {
        bytes memory settings = abi.encode("1) What", "2) H", 9000000000, 0);

        vm.prank(deployer);
        registry.updateSettings(vaultType, settings);

        vm.prank(user);
        settings = registry.getSettings(vaultType);

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

    function test_setImplementation() public {
        vm.prank(deployer);
        registry.setImplementation(vaultType, address(123));

        assert(registry.hasImplementation(vaultType));
    }

    function test_setImplementation_revertIf_NotOwner() public {
        vm.prank(user);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        registry.setImplementation(vaultType, address(123));

        assert(!registry.hasImplementation(vaultType));
    }

    function test_getImplementation() public {
        vm.prank(deployer);
        registry.setImplementation(vaultType, address(123));

        vm.prank(user);
        address impl = registry.getImplementation(vaultType);

        assertEq(impl, address(123));
    }
}
