// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {Assertions} from "../Assertions.sol";
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

    function hasImplementation(bytes32 vaultType) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.implementations[vaultType] != address(0);
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

        // Add vaults
        registry.addVault(
            address(10),
            keccak256("Vault1"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );
        registry.addVault(
            address(11),
            keccak256("Vault1"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Put
        );
        registry.addVault(
            address(12),
            keccak256("Vault2"),
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Call
        );
        registry.addVault(
            address(13),
            keccak256("Vault2"),
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Put
        );
        registry.addVault(
            address(14),
            keccak256("Vault3"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );
        registry.addVault(
            address(15),
            keccak256("Vault3"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Put
        );
        registry.addVault(
            address(16),
            keccak256("Vault3"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );
        registry.addVault(
            address(17),
            keccak256("Vault3"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Put
        );
        registry.addVault(
            address(18),
            keccak256("Vault4"),
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Both
        );
        registry.addVault(
            address(19),
            keccak256("Vault4"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Both
        );
        registry.addVault(
            address(20),
            keccak256("Vault4"),
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Both
        );

        vm.stopPrank();
    }

    function test_isVault() public {
        assertEq(registry.isVault(address(10)), true);
        assertEq(registry.isVault(address(17)), true);
        assertEq(registry.isVault(address(0)), false);
    }

    function test_getVault() public {
        IVaultRegistry.Vault memory vault = registry.getVault(address(10));
        assertEq(vault.vault, address(10));
        assertEq(vault.vaultType, keccak256("Vault1"));
        assertEq(uint8(vault.side), uint8(IVaultRegistry.TradeSide.Sell));
        assertEq(
            uint8(vault.optionType),
            uint8(IVaultRegistry.OptionType.Call)
        );

        vault = registry.getVault(address(17));
        assertEq(vault.vault, address(17));
        assertEq(vault.vaultType, keccak256("Vault3"));
        assertEq(uint8(vault.side), uint8(IVaultRegistry.TradeSide.Sell));
        assertEq(uint8(vault.optionType), uint8(IVaultRegistry.OptionType.Put));
    }

    function test_getVaults() public {
        vm.prank(user);

        IVaultRegistry.Vault[] memory vaults = registry.getVaults();

        assertEq(vaults.length, 11);

        assertEq(vaults[3].vault, address(13));
        assertEq(vaults[3].vaultType, keccak256("Vault2"));
        assertEq(uint8(vaults[3].side), uint8(IVaultRegistry.TradeSide.Both));
        assertEq(
            uint8(vaults[3].optionType),
            uint8(IVaultRegistry.OptionType.Put)
        );
    }

    function test_getVaultsByFilter() public {
        vm.prank(user);

        // 1. [buy] [call]
        IVaultRegistry.Vault[] memory vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Call
        );

        assertEq(vaults.length, 4);
        assertEq(vaults[0].vault, address(12));

        //2. [buy] [put]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Put
        );

        assertEq(vaults.length, 4);
        assertEq(vaults[0].vault, address(13));

        // 3. [buy] [both]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Buy,
            IVaultRegistry.OptionType.Both
        );

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(18));

        // 4. [sell] [call]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        assertEq(vaults.length, 5);
        assertEq(vaults[0].vault, address(10));

        // 5. [sell] [put]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Put
        );

        assertEq(vaults.length, 5);
        assertEq(vaults[0].vault, address(11));

        // 6. [sell] [both]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Both
        );

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(19));

        // 7. [both] [call]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Call
        );

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(12));

        // 8. [both] [put]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Put
        );

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(13));

        // 9. [both] [both]
        vaults = registry.getVaultsByFilter(
            IVaultRegistry.TradeSide.Both,
            IVaultRegistry.OptionType.Both
        );

        assertEq(vaults.length, 1);
        assertEq(vaults[0].vault, address(20));
    }

    function test_getVaultByTradeSide() public {
        // Buy
        IVaultRegistry.Vault[] memory vaults = registry.getVaultsByTradeSide(
            IVaultRegistry.TradeSide.Buy
        );

        assertEq(vaults.length, 6);

        // Sell
        vaults = registry.getVaultsByTradeSide(IVaultRegistry.TradeSide.Sell);

        assertEq(vaults.length, 8);
        assertEq(vaults[0].vault, address(10));

        // Both
        vaults = registry.getVaultsByTradeSide(IVaultRegistry.TradeSide.Both);

        assertEq(vaults.length, 3);
    }

    function test_getVaultByOptionType() public {
        // Call
        IVaultRegistry.Vault[] memory vaults = registry.getVaultsByOptionType(
            IVaultRegistry.OptionType.Call
        );

        assertEq(vaults.length, 7);
        assertEq(vaults[0].vault, address(10));

        // Put
        vaults = registry.getVaultsByOptionType(IVaultRegistry.OptionType.Put);

        assertEq(vaults.length, 7);
        assertEq(vaults[0].vault, address(11));

        // Both
        vaults = registry.getVaultsByOptionType(IVaultRegistry.OptionType.Both);

        assertEq(vaults.length, 3);
        assertEq(vaults[0].vault, address(18));
    }

    function test_getVaultByType() public {
        // Vault 1
        IVaultRegistry.Vault[] memory vaults = registry.getVaultsByType(
            keccak256("Vault1")
        );

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(10));

        // Vault 2
        vaults = registry.getVaultsByType(keccak256("Vault2"));

        assertEq(vaults.length, 2);
        assertEq(vaults[0].vault, address(12));

        // Vault 3
        vaults = registry.getVaultsByType(keccak256("Vault3"));

        assertEq(vaults.length, 4);
        assertEq(vaults[0].vault, address(14));

        // Vault 4
        vaults = registry.getVaultsByType(keccak256("Vault4"));

        assertEq(vaults.length, 3);
        assertEq(vaults[0].vault, address(18));
    }
}
