// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

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
        address asset,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaults[vault] = Vault(vault, asset, vaultType, side, optionType);

        l.vaultAddresses.add(vault);
        l.vaultsByType[vaultType].add(vault);
        l.vaultsByAsset[asset].add(vault);
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

        emit VaultAdded(vault, asset, vaultType, side, optionType);
    }

    /// @inheritdoc IVaultRegistry
    function removeVault(address vault) public onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        l.vaultAddresses.remove(vault);
        l.vaultsByType[l.vaults[vault].vaultType].remove(vault);
        l.vaultsByAsset[l.vaults[vault].asset].remove(vault);
        l.vaultsByTradeSide[l.vaults[vault].side].remove(vault);
        l.vaultsByOptionType[l.vaults[vault].optionType].remove(vault);

        for (uint256 i = 0; i < l.supportedTokenPairs[vault].length; i++) {
            TokenPair memory pair = l.supportedTokenPairs[vault][i];
            l.vaultsByTokenPair[pair.base][pair.quote][pair.oracleAdapter].remove(vault);
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
        delete l.supportedTokenPairs[vault];

        emit VaultRemoved(vault);
    }

    /// @inheritdoc IVaultRegistry
    function isVault(address vault) external view returns (bool) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaultAddresses.contains(vault);
    }

    /// @inheritdoc IVaultRegistry
    function updateVault(
        address vault,
        address asset,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        if (l.vaults[vault].asset != asset) {
            l.vaultsByAsset[l.vaults[vault].asset].remove(vault);
            l.vaultsByAsset[asset].add(vault);
        }

        if (l.vaults[vault].vaultType != vaultType) {
            l.vaultsByType[l.vaults[vault].vaultType].remove(vault);
            l.vaultsByType[vaultType].add(vault);
        }

        if (l.vaults[vault].side != side) {
            if (l.vaults[vault].side == TradeSide.Both) {
                l.vaultsByTradeSide[TradeSide.Buy].remove(vault);
                l.vaultsByTradeSide[TradeSide.Sell].remove(vault);
            } else {
                l.vaultsByTradeSide[l.vaults[vault].side].remove(vault);
            }

            if (side == TradeSide.Both) {
                l.vaultsByTradeSide[TradeSide.Buy].add(vault);
                l.vaultsByTradeSide[TradeSide.Sell].add(vault);
            } else {
                l.vaultsByTradeSide[side].add(vault);
            }
        }

        if (l.vaults[vault].optionType != optionType) {
            if (l.vaults[vault].optionType == OptionType.Both) {
                l.vaultsByOptionType[OptionType.Call].remove(vault);
                l.vaultsByOptionType[OptionType.Put].remove(vault);
            } else {
                l.vaultsByOptionType[l.vaults[vault].optionType].remove(vault);
            }

            if (optionType == OptionType.Both) {
                l.vaultsByOptionType[OptionType.Call].add(vault);
                l.vaultsByOptionType[OptionType.Put].add(vault);
            } else {
                l.vaultsByOptionType[optionType].add(vault);
            }
        }

        l.vaults[vault] = Vault(vault, asset, vaultType, side, optionType);

        emit VaultUpdated(vault, asset, vaultType, side, optionType);
    }

    /// @inheritdoc IVaultRegistry
    function addSupportedTokenPairs(address vault, TokenPair[] memory tokenPairs) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        for (uint256 i = 0; i < tokenPairs.length; i++) {
            l.supportedTokenPairs[vault].push(tokenPairs[i]);
            l.vaultsByTokenPair[tokenPairs[i].base][tokenPairs[i].quote][tokenPairs[i].oracleAdapter].add(vault);
        }
    }

    /// @notice Returns true if `tokenPairs` contains `tokenPair`, false otherwise
    function _containsTokenPair(
        TokenPair[] memory tokenPairs,
        TokenPair memory tokenPair
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < tokenPairs.length; i++) {
            if (
                tokenPairs[i].base == tokenPair.base &&
                tokenPairs[i].quote == tokenPair.quote &&
                tokenPairs[i].oracleAdapter == tokenPair.oracleAdapter
            ) {
                return true;
            }
        }

        return false;
    }

    /// @inheritdoc IVaultRegistry
    function removeSupportedTokenPairs(address vault, TokenPair[] memory tokenPairsToRemove) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();

        for (uint256 i = 0; i < tokenPairsToRemove.length; i++) {
            l
            .vaultsByTokenPair[tokenPairsToRemove[i].base][tokenPairsToRemove[i].quote][
                tokenPairsToRemove[i].oracleAdapter
            ].remove(vault);
        }

        uint256 length = l.supportedTokenPairs[vault].length;
        TokenPair[] memory newTokenPairs = new TokenPair[](length);

        uint256 count = 0;
        for (uint256 i = 0; i < length; i++) {
            if (!_containsTokenPair(tokenPairsToRemove, l.supportedTokenPairs[vault][i])) {
                newTokenPairs[count] = l.supportedTokenPairs[vault][i];
                count++;
            }
        }

        delete l.supportedTokenPairs[vault];

        for (uint256 i = 0; i < count; i++) {
            l.supportedTokenPairs[vault].push(newTokenPairs[i]);
        }
    }

    /// @inheritdoc IVaultRegistry
    function getVault(address vault) external view returns (Vault memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.vaults[vault];
    }

    /// @inheritdoc IVaultRegistry
    function getSupportedTokenPairs(address vault) external view returns (TokenPair[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.supportedTokenPairs[vault];
    }

    /// @notice Returns an array of vaults from a set of vault addresses
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
            Vault memory vault = l.vaults[l.vaultsByOptionType[optionType].at(i)];

            if (vault.side == side || vault.side == TradeSide.Both) {
                bool assetFound = false;

                if (assets.length == 0) {
                    assetFound = true;
                } else {
                    for (uint256 j = 0; j < assets.length; j++) {
                        if (vault.asset == assets[j]) {
                            assetFound = true;
                            break;
                        }
                    }
                }

                if (assetFound) {
                    vaults[count] = vault;
                    count++;
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
    function getVaultsByAsset(address asset) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByAsset[asset]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByTokenPair(TokenPair memory tokenPair) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByTokenPair[tokenPair.base][tokenPair.quote][tokenPair.oracleAdapter]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByTradeSide(TradeSide side) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByTradeSide[side]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByOptionType(OptionType optionType) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByOptionType[optionType]);
    }

    /// @inheritdoc IVaultRegistry
    function getVaultsByType(bytes32 vaultType) external view returns (Vault[] memory) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return _getVaultsFromAddressSet(l.vaultsByType[vaultType]);
    }

    /// @inheritdoc IVaultRegistry
    function getImplementation(bytes32 vaultType) external view returns (address) {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        return l.implementations[vaultType];
    }

    /// @inheritdoc IVaultRegistry
    function setImplementation(bytes32 vaultType, address implementation) external onlyOwner {
        VaultRegistryStorage.Layout storage l = VaultRegistryStorage.layout();
        l.implementations[vaultType] = implementation;

        emit VaultImplementationSet(vaultType, implementation);
    }
}
