// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {IVaultRegistry} from "./IVaultRegistry.sol";
import {VaultRegistryStorage} from "./VaultRegistryStorage.sol";

contract VaultRegistry is IVaultRegistry, OwnableInternal {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

    function vault(address _vaultAddress) external view returns (Vault memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults[_vaultAddress];
    }

    function vaultAddress(uint256 index) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.at(index);
    }

    function vaults() external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](l.vaultAddresses.length());
        for (uint256 i = 0; i < l.vaultAddresses.length(); i++) {
            vaultsToReturn[i] = l.vaults[l.vaultAddresses.at(i)];
        }
        return vaultsToReturn;
    }

    function vaultsPerTradeSide(
        TradeSide side
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](
            l.vaultsPerTradeSide[side].length()
        );
        for (uint256 i = 0; i < l.vaultsPerTradeSide[side].length(); i++) {
            vaultsToReturn[i] = l.vaults[l.vaultsPerTradeSide[side].at(i)];
        }
        return vaultsToReturn;
    }

    function vaultsPerOptionType(
        OptionType optionType
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault[] memory vaultsToReturn = new Vault[](
            l.vaultsPerOptionType[optionType].length()
        );
        for (
            uint256 i = 0;
            i < l.vaultsPerOptionType[optionType].length();
            i++
        ) {
            vaultsToReturn[i] = l.vaults[
                l.vaultsPerOptionType[optionType].at(i)
            ];
        }
        return vaultsToReturn;
    }

    function vaultsLength() external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.length();
    }

    function getVaults(
        IVaultRegistry.TradeSide[] memory sides,
        IVaultRegistry.OptionType[] memory optionTypes
    ) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        uint256 length = l.vaultAddresses.length();
        Vault[] memory vaultsToReturn = new Vault[](length);

        uint256 index = 0;
        bool breakToVaultAddress;
        for (uint256 i = 0; i < l.vaultAddresses.length(); i++) {
            address _vaultAddress = l.vaultAddresses.at(i);
            Vault memory _vault = l.vaults[_vaultAddress];

            breakToVaultAddress = false;

            for (uint256 j = 0; j < sides.length; j++) {
                if (breakToVaultAddress) break;

                if (_vault.side == sides[j]) {
                    for (uint256 k = 0; k < optionTypes.length; k++) {
                        if (_vault.optionType == optionTypes[k]) {
                            vaultsToReturn[index] = _vault;
                            index++;

                            breakToVaultAddress = true;
                            break;
                        }
                    }
                }
            }
        }

        // Remove empty elements from array
        if (index < length) {
            assembly {
                mstore(
                    vaultsToReturn,
                    sub(mload(vaultsToReturn), sub(length, index))
                )
            }
        }

        return vaultsToReturn;
    }

    function addVault(
        address _vault,
        IVaultRegistry.TradeSide side,
        IVaultRegistry.OptionType optionType
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaults[_vault] = Vault(_vault, side, optionType);

        l.vaultAddresses.add(_vault);
        l.vaultsPerTradeSide[side].add(_vault);
        l.vaultsPerOptionType[optionType].add(_vault);

        emit VaultAdded(_vault, side, optionType);
    }

    function removeVault(address _vaultAddress) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        Vault memory _vault = l.vaults[_vaultAddress];

        l.vaultAddresses.remove(_vault.vault);
        l.vaultsPerTradeSide[_vault.side].remove(_vault.vault);
        l.vaultsPerOptionType[_vault.optionType].remove(_vault.vault);

        emit VaultRemoved(_vault.vault);
    }
}
