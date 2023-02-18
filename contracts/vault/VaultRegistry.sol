// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IVaultRegistry} from "./IVaultRegistry.sol";

contract VaultRegistry {
    mapping (address => IVaultRegistry.TradeSide) public vaultTradeSide;
    mapping (address => IVaultRegistry.OptionType) public vaultOptionType;

    mapping (IVaultRegistry.TradeSide => address[]) public vaultsPerTradeSide;
    mapping (IVaultRegistry.OptionType => address[]) public vaultsPerOptionType;
    address[] public vaults;

    function vaultsLength() external view returns (uint256) {
        return vaults.length;
    }

    function vaultsPerTradeSideLength(IVaultRegistry.TradeSide side) external view returns (uint256) {
        return vaultsPerTradeSide[side].length;
    }

    function vaultsPerOptionTypeLength(IVaultRegistry.OptionType optionType) external view returns (uint256) {
        return vaultsPerOptionType[optionType].length;
    }

    function vault(uint256 index) external view returns (address) {
        return vaults[index];
    }

    function getVaults(IVaultRegistry.TradeSide side, IVaultRegistry.OptionType optionType) external view returns (address[] memory) {
        address[] memory _vaultsPerTradeSide = vaultsPerTradeSide[side];
        address[] memory _vaultsPerOptionType = vaultsPerOptionType[optionType];
        address[] memory vaultsToReturn = new address[](_vaultsPerTradeSide.length + _vaultsPerOptionType.length);
        uint256 index = 0;
        for (uint256 i = 0; i < _vaultsPerTradeSide.length; i++) {
            vaultsToReturn[index] = _vaultsPerTradeSide[i];
            index++;
        }
        for (uint256 i = 0; i < _vaultsPerOptionType.length; i++) {
            vaultsToReturn[index] = _vaultsPerOptionType[i];
            index++;
        }
        return vaultsToReturn;
    }

    function getVaults(
        IVaultRegistry.TradeSide[] memory sides,
        IVaultRegistry.OptionType[] memory optionTypes
    ) external view returns (address[] memory) {
        address[] memory vaultsToReturn = new address[](vaults.length);
        uint256 index = 0;
        for (uint256 i = 0; i < sides.length; i++) {
            address[] memory _vaultsPerTradeSide = vaultsPerTradeSide[sides[i]];
            for (uint256 j = 0; j < _vaultsPerTradeSide.length; j++) {
                vaultsToReturn[index] = _vaultsPerTradeSide[j];
                index++;
            }
        }
        for (uint256 i = 0; i < optionTypes.length; i++) {
            address[] memory _vaultsPerOptionType = vaultsPerOptionType[optionTypes[i]];
            for (uint256 j = 0; j < _vaultsPerOptionType.length; j++) {
                vaultsToReturn[index] = _vaultsPerOptionType[j];
                index++;
            }
        }
        return vaultsToReturn;
    }

    function addVault(address _vault, IVaultRegistry.TradeSide side, IVaultRegistry.OptionType optionType) external {
        vaultTradeSide[_vault] = side;
        vaultOptionType[_vault] = optionType;
        vaultsPerTradeSide[side].push(_vault);
        vaultsPerOptionType[optionType].push(_vault);
        vaults.push(_vault);
    }

    function removeVault(uint256 index) external {
        removeVaultPerTradeSide(vaults[index]);
        removeVaultPerOptionType(vaults[index]);

        vaults[index] = vaults[vaults.length - 1];
        vaults.pop();
    }

    function removeVault(address _vault) external {
        removeVaultPerTradeSide(_vault);
        removeVaultPerOptionType(_vault);

        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == _vault) {
                vaults[i] = vaults[vaults.length - 1];
                vaults.pop();
                break;
            }
        }
    }

    function removeVaultPerTradeSide(address _vault) internal {
        IVaultRegistry.TradeSide side = vaultTradeSide[_vault];
        for (uint256 i = 0; i < vaultsPerTradeSide[side].length; i++) {
            if (vaultsPerTradeSide[side][i] == _vault) {
                vaultsPerTradeSide[side][i] = vaultsPerTradeSide[side][vaultsPerTradeSide[side].length - 1];
                vaultsPerTradeSide[side].pop();
                break;
            }
        }
    }

    function removeVaultPerOptionType(address _vault) internal {
        IVaultRegistry.OptionType optionType = vaultOptionType[_vault];
        for (uint256 i = 0; i < vaultsPerOptionType[optionType].length; i++) {
            if (vaultsPerOptionType[optionType][i] == _vault) {
                vaultsPerOptionType[optionType][i] = vaultsPerOptionType[optionType][vaultsPerOptionType[optionType].length - 1];
                vaultsPerOptionType[optionType].pop();
                break;
            }
        }
    }
}
