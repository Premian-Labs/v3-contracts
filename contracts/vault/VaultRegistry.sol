// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

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
        address[] memory assets,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType,
        string memory name
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaults[vault] = Vault(
            vault,
            assets,
            vaultType,
            side,
            optionType,
            name
        );

        l.vaultAddresses.add(vault);
        l.vaultsByType[vaultType].add(vault);
        l.vaultsByTradeSide[side].add(vault);
        l.vaultsByOptionType[optionType].add(vault);

        for (uint256 i = 0; i < assets.length; i++) {
            l.vaultsByAsset[assets[i]].add(vault);
        }

        if (side == TradeSide.Both) {
            l.vaultsByTradeSide[TradeSide.Buy].add(vault);
            l.vaultsByTradeSide[TradeSide.Sell].add(vault);
        }

        if (optionType == OptionType.Both) {
            l.vaultsByOptionType[OptionType.Call].add(vault);
            l.vaultsByOptionType[OptionType.Put].add(vault);
        }

        emit VaultAdded(vault, assets, vaultType, side, optionType, name);
    }

    /// @inheritdoc IVaultRegistry
    function removeVault(address vault) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaultAddresses.remove(vault);
        l.vaultsByType[l.vaults[vault].vaultType].remove(vault);
        l.vaultsByTradeSide[l.vaults[vault].side].remove(vault);
        l.vaultsByOptionType[l.vaults[vault].optionType].remove(vault);

        for (uint i = 0; i < l.vaults[vault].assets.length; i++) {
            l.vaultsByAsset[l.vaults[vault].assets[i]].remove(vault);
        }

        if (l.vaults[vault].side == TradeSide.Both) {
            l.vaultsByTradeSide[TradeSide.Buy].remove(vault);
            l.vaultsByTradeSide[TradeSide.Sell].remove(vault);
        }

        if (l.vaults[vault].optionType == OptionType.Both) {
            l.vaultsByOptionType[OptionType.Call].remove(vault);
            l.vaultsByOptionType[OptionType.Put].remove(vault);
        }

        delete l.vaults[vault];

        emit VaultRemoved(vault);
    }

    /// @inheritdoc IVaultRegistry
    function getVault(address vault) external view returns (Vault memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults[vault];
    }

    function _getVaultsFromAddressSet(
        EnumerableSet.AddressSet storage vaultSet
    ) internal view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 length = vaultSet.length();
        Vault[] memory vaults = new Vault[](length);

        for (uint256 i = 0; i < length; i++) {
            vaults[i] = l.vaults[vaultSet.at(i)];
        }
        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaults() external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultAddresses);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByFilter(
        address[] memory assets,
        TradeSide side,
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 length = l.vaultsByOptionType[optionType].length();
        Vault[] memory vaults = new Vault[](length);

        uint256 count;
        for (uint256 i = 0; i < length; i++) {
            Vault memory vault = l.vaults[
                l.vaultsByOptionType[optionType].at(i)
            ];

            if (vault.side == side || vault.side == TradeSide.Both) {
                bool assetFound = false;

                if (assets.length == 0) {
                    assetFound = true;
                } else {
                    for (uint256 j = 0; j < assets.length; j++) {
                        if (assetFound) break;

                        for (uint k = 0; k < vault.assets.length; k++) {
                            if (vault.assets[k] == assets[j]) {
                                assetFound = true;
                                break;
                            }
                        }
                    }
                }

                if (assetFound) {
                    vaults[count] = vault;
                    count++;
                    break;
                }
            }
        }

        // Remove empty elements from array
        if (count < length) {
            assembly {
                mstore(vaults, count)
            }
        }

        return vaults;
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByAsset(
        address asset
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByAsset[asset]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByTradeSide(
        TradeSide side
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByTradeSide[side]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByOptionType(
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByOptionType[optionType]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByType(
        bytes32 vaultType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByType[vaultType]);
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
