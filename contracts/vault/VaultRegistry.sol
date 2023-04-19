// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IVault} from "./IVault.sol";
import {IVaultRegistry} from "./IVaultRegistry.sol";
import {VaultRegistryStorage} from "./VaultRegistryStorage.sol";

contract VaultRegistry is IVaultRegistry, OwnableInternal {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IVaultRegistry
    function getNumberOfVaults() external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.length();
    }

    /// @inheritdoc IVaultRegistry
    function addVault(
        address vault,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaults[vault] = Vault(vault, vaultType, side, optionType);

        l.vaultAddresses.add(vault);
        l.vaultsByType[vaultType].add(vault);
        l.vaultsByTradeSide[side].add(vault);
        l.vaultsByOptionType[optionType].add(vault);

        if (side == TradeSide.Both) {
            l.vaultsByTradeSide[TradeSide.Buy].add(vault);
            l.vaultsByTradeSide[TradeSide.Sell].add(vault);
        }

        if (optionType == OptionType.Both) {
            l.vaultsByOptionType[OptionType.Call].add(vault);
            l.vaultsByOptionType[OptionType.Put].add(vault);
        }

        emit VaultAdded(vault, vaultType, side, optionType);
    }

    /// @inheritdoc IVaultRegistry
    function removeVault(address vault) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault memory _vault = l.vaults[vault];

        l.vaultAddresses.remove(_vault.vault);
        l.vaultsByTradeSide[_vault.side].remove(_vault.vault);
        l.vaultsByOptionType[_vault.optionType].remove(_vault.vault);

        emit VaultRemoved(_vault.vault);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultAddressAt(uint256 index) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.at(index);
    }

    /// @inheritdoc IVaultRegistry
    function getVault(address vault) external view returns (Vault memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults[vault];
    }

    /// @inheritdoc IVaultRegistry
    function getVaults() external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaults = new Vault[](l.vaultAddresses.length());
        for (uint256 i = 0; i < l.vaultAddresses.length(); i++) {
            vaults[i] = l.vaults[l.vaultAddresses.at(i)];
        }
        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByFilter(
        TradeSide side,
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 n = l.vaultsByOptionType[optionType].length();
        Vault[] memory vaults = new Vault[](n);

        uint256 index;
        for (uint256 i = 0; i < n; i++) {
            Vault memory vault = l.vaults[
                l.vaultsByOptionType[optionType].at(i)
            ];

            if (vault.side == side || vault.side == TradeSide.Both) {
                vaults[index] = vault;
                index++;
            }
        }

        // Remove empty elements from array
        if (index < n) {
            assembly {
                mstore(vaults, index)
            }
        }

        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByTradeSide(
        TradeSide side
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        Vault[] memory vaults = new Vault[](l.vaultsByTradeSide[side].length());
        uint256 n = l.vaultsByTradeSide[side].length();

        for (uint256 i = 0; i < n; i++) {
            vaults[i] = l.vaults[l.vaultsByTradeSide[side].at(i)];
        }
        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByOptionType(
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 n = l.vaultsByOptionType[optionType].length();
        Vault[] memory vaults = new Vault[](n);

        for (uint256 i = 0; i < n; i++) {
            vaults[i] = l.vaults[l.vaultsByOptionType[optionType].at(i)];
        }
        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByType(
        bytes32 vaultType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 n = l.vaultsByType[vaultType].length();
        Vault[] memory vaults = new Vault[](n);

        for (uint256 i = 0; i < n; i++) {
            vaults[i] = l.vaults[l.vaultsByType[vaultType].at(i)];
        }
        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.settings[vaultType];
    }

    /// @inheritdoc IVaultRegistry
    function updateSettings(
        bytes32 vaultType,
        bytes memory updatedSettings
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        l.settings[vaultType] = updatedSettings;

        // Loop through the vaults == vaultType
        for (uint256 i = 0; i < l.vaultsByType[vaultType].length(); i++) {
            IVault(l.vaultsByType[vaultType].at(i)).updateSettings(
                updatedSettings
            );
        }
    }

    /// @inheritdoc IVaultRegistry
    function getImplementation(
        bytes32 vaultType
    ) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.implementations[vaultType];
    }

    /// @inheritdoc IVaultRegistry
    function setImplementation(
        bytes32 vaultType,
        address implementation
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        l.implementations[vaultType] = implementation;
    }
}
