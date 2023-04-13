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

    function getNumberOfVaults() external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.length();
    }

    function addVault(
        address _vault,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaults[_vault] = Vault(_vault, vaultType, side, optionType);

        l.vaultAddresses.add(_vault);
        l.vaultsByType[vaultType].add(_vault);
        l.vaultsByTradeSide[side].add(_vault);
        l.vaultsByOptionType[optionType].add(_vault);

        emit VaultAdded(_vault, vaultType, side, optionType);
    }

    function removeVault(address _vaultAddress) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault memory _vault = l.vaults[_vaultAddress];

        l.vaultAddresses.remove(_vault.vault);
        l.vaultsByTradeSide[_vault.side].remove(_vault.vault);
        l.vaultsByOptionType[_vault.optionType].remove(_vault.vault);

        emit VaultRemoved(_vault.vault);
    }

    function getVaultAddressAt(uint256 index) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.at(index);
    }

    function getVault(
        address _vaultAddress
    ) external view returns (Vault memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults[_vaultAddress];
    }

    function getVaults() external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](l.vaultAddresses.length());
        for (uint256 i = 0; i < l.vaultAddresses.length(); i++) {
            vaultsToReturn[i] = l.vaults[l.vaultAddresses.at(i)];
        }
        return vaultsToReturn;
    }

    function getVaultsByFilter(
        TradeSide[] memory sides,
        OptionType[] memory optionTypes
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 n = l.vaultAddresses.length();
        Vault[] memory vaults = new Vault[](n);

        uint256 index;

        for (uint256 i = 0; i < n; i++) {
            Vault memory vault = l.vaults[l.vaultAddresses.at(i)];

            bool isDone = false;

            for (uint256 j = 0; j < sides.length; j++) {
                if (isDone) break;

                if (vault.side == sides[j]) {
                    for (uint256 k = 0; k < optionTypes.length; k++) {
                        if (vault.optionType == optionTypes[k]) {
                            vaults[index] = vault;
                            index++;

                            isDone = true;
                            break;
                        }
                    }
                }
            }
        }

        // Remove empty elements from array
        if (index < n) {
            assembly {
                mstore(vaults, sub(mload(vaults), sub(n, index)))
            }
        }

        return vaults;
    }

    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.settings[vaultType];
    }

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

    function getImplementation(
        bytes32 vaultType
    ) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.implementations[vaultType];
    }

    function setImplementation(
        bytes32 vaultType,
        address implementation
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        l.implementations[vaultType] = implementation;
    }

    function getVaultsByTradeSide(
        TradeSide side
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](
            l.vaultsByTradeSide[side].length()
        );
        for (uint256 i = 0; i < l.vaultsByTradeSide[side].length(); i++) {
            vaultsToReturn[i] = l.vaults[l.vaultsByTradeSide[side].at(i)];
        }
        return vaultsToReturn;
    }

    function getVaultsByOptionType(
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](
            l.vaultsByOptionType[optionType].length()
        );
        for (
            uint256 i = 0;
            i < l.vaultsByOptionType[optionType].length();
            i++
        ) {
            vaultsToReturn[i] = l.vaults[
                l.vaultsByOptionType[optionType].at(i)
            ];
        }
        return vaultsToReturn;
    }

    function getVaultsByType(
        bytes32 vaultType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](
            l.vaultsByType[vaultType].length()
        );
        for (uint256 i = 0; i < l.vaultsByType[vaultType].length(); i++) {
            vaultsToReturn[i] = l.vaults[l.vaultsByType[vaultType].at(i)];
        }
        return vaultsToReturn;
    }
}
