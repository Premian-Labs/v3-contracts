// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {VaultRegistryStorage} from "./VaultRegistryStorage.sol";
import {IVaultRegistry} from "./IVaultRegistry.sol";

contract VaultRegistry is IVaultRegistry, SafeOwnable {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;
    using EnumerableSet for EnumerableSet.AddressSet;

    function vault(uint256 index) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults.at(index);
    }

    function vaults() external view returns (address[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        address[] memory vaultsToReturn = new address[](l.vaults.length());
        for (uint256 i = 0; i < l.vaults.length(); i++) {
            vaultsToReturn[i] = l.vaults.at(i);
        }
        return vaultsToReturn;
    }

    function vaultsPerTradeSide(TradeSide side) external view returns (address[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        address[] memory vaultsToReturn = new address[](l.vaultsPerTradeSide[side].length());
        for (uint256 i = 0; i < l.vaultsPerTradeSide[side].length(); i++) {
            vaultsToReturn[i] = l.vaultsPerTradeSide[side].at(i);
        }
        return vaultsToReturn;
    }

    function vaultsPerOptionType(OptionType optionType) external view returns (address[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        address[] memory vaultsToReturn = new address[](l.vaultsPerOptionType[optionType].length());
        for (uint256 i = 0; i < l.vaultsPerOptionType[optionType].length(); i++) {
            vaultsToReturn[i] = l.vaultsPerOptionType[optionType].at(i);
        }
        return vaultsToReturn;
    }

    function vaultsLength() external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults.length();
    }

    function vaultsPerTradeSideLength(IVaultRegistry.TradeSide side) external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultsPerTradeSide[side].length();
    }

    function vaultsPerOptionTypeLength(IVaultRegistry.OptionType optionType) external view returns (uint256) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultsPerOptionType[optionType].length();
    }

    function getVaults(IVaultRegistry.TradeSide side, IVaultRegistry.OptionType optionType) external view returns (address[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        EnumerableSet.AddressSet storage _vaultsPerTradeSide = l.vaultsPerTradeSide[side];
        EnumerableSet.AddressSet storage _vaultsPerOptionType = l.vaultsPerOptionType[optionType];
        address[] memory vaultsToReturn = new address[](_vaultsPerTradeSide.length() + _vaultsPerOptionType.length());
        uint256 index = 0;
        for (uint256 i = 0; i < _vaultsPerTradeSide.length(); i++) {
            vaultsToReturn[index] = _vaultsPerTradeSide.at(i);
            index++;
        }
        for (uint256 i = 0; i < _vaultsPerOptionType.length(); i++) {
            vaultsToReturn[index] = _vaultsPerOptionType.at(i);
            index++;
        }
        return vaultsToReturn;
    }

    function getVaults(
        IVaultRegistry.TradeSide[] memory sides,
        IVaultRegistry.OptionType[] memory optionTypes
    ) external view returns (address[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        address[] memory vaultsToReturn = new address[](l.vaults.length());
        uint256 index = 0;
        for (uint256 i = 0; i < sides.length; i++) {
            EnumerableSet.AddressSet storage _vaultsPerTradeSide = l.vaultsPerTradeSide[sides[i]];
            for (uint256 j = 0; j < _vaultsPerTradeSide.length(); j++) {
                vaultsToReturn[index] = _vaultsPerTradeSide.at(j);
                index++;
            }
        }
        for (uint256 i = 0; i < optionTypes.length; i++) {
            EnumerableSet.AddressSet storage _vaultsPerOptionType = l.vaultsPerOptionType[optionTypes[i]];
            for (uint256 j = 0; j < _vaultsPerOptionType.length(); j++) {
                vaultsToReturn[index] = _vaultsPerOptionType.at(j);
                index++;
            }
        }
        return vaultsToReturn;
    }

    function addVault(address _vault, IVaultRegistry.TradeSide side, IVaultRegistry.OptionType optionType) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        
        l.vaultTradeSide[_vault] = side;
        l.vaultOptionType[_vault] = optionType;
        l.vaultsPerTradeSide[side].add(_vault);
        l.vaultsPerOptionType[optionType].add(_vault);
        l.vaults.add(_vault);

        emit VaultAdded(_vault, side, optionType);
    }

    function removeVault(uint256 index) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        removeVault(l.vaults.at(index));
    }

    function removeVault(address _vault) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        IVaultRegistry.TradeSide side = l.vaultTradeSide[_vault];
        IVaultRegistry.OptionType optionType = l.vaultOptionType[_vault];

        l.vaults.remove(_vault);
        l.vaultsPerTradeSide[side].remove(_vault);
        l.vaultsPerOptionType[optionType].remove(_vault);

        emit VaultRemoved(_vault);
    }
}
