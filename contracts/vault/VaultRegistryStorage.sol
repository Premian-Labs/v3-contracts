// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IVaultRegistry} from "./IVaultRegistry.sol";

library VaultRegistryStorage {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VaultRegistry");

    struct Layout {
        EnumerableSet.AddressSet vaultAddresses;
        mapping(bytes32 => bytes) settings;
        mapping(bytes32 => address) implementations;
        mapping(address => IVaultRegistry.Vault) vaults;
        mapping(bytes32 => EnumerableSet.AddressSet) vaultsByType;
        mapping(IVaultRegistry.TradeSide => EnumerableSet.AddressSet) vaultsPerTradeSide;
        mapping(IVaultRegistry.OptionType => EnumerableSet.AddressSet) vaultsPerOptionType;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
