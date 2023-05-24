// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IVaultRegistry} from "./IVaultRegistry.sol";

library VaultRegistryStorage {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.VaultRegistry");

    struct Layout {
        EnumerableSet.AddressSet vaultAddresses;
        mapping(bytes32 vaultType => bytes) settings;
        mapping(bytes32 vaultType => address) implementations;
        mapping(address vault => IVaultRegistry.Vault) vaults;
        mapping(address vault => IVaultRegistry.TokenPair[] supported) supportedTokenPairs;
        mapping(bytes32 vaultType => EnumerableSet.AddressSet vaults) vaultsByType;
        mapping(address asset => EnumerableSet.AddressSet vaults) vaultsByAsset;
        mapping(address base => mapping(address quote => mapping(address oracleAdapter => EnumerableSet.AddressSet vaults))) vaultsByTokenPair;
        mapping(IVaultRegistry.TradeSide tradeSide => EnumerableSet.AddressSet vaults) vaultsByTradeSide;
        mapping(IVaultRegistry.OptionType optionType => EnumerableSet.AddressSet vaults) vaultsByOptionType;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
