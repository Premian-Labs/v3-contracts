// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IVaultRegistry} from "./IVaultRegistry.sol";

library VaultRegistryStorage {
    using VaultRegistryStorage for VaultRegistryStorage.Layout;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.VaultRegistry");

    struct Layout {
        EnumerableSet.AddressSet vaultAddresses;
        mapping(address => IVaultRegistry.Vault) vaults;
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
