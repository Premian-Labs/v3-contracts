// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

interface IVaultRegistry {
    enum TradeSide {
        Buy,
        Sell,
        Both
    }
    enum OptionType {
        Call,
        Put,
        Both
    }

    struct Vault {
        address vault;
        TradeSide side;
        OptionType optionType;
    }

    event VaultAdded(
        address indexed vault,
        TradeSide side,
        OptionType optionType
    );
    event VaultRemoved(address indexed vault);

    function vault(address vaultAddress) external view returns (Vault memory);

    function vaultAddress(uint256 index) external view returns (address);

    function vaults() external view returns (Vault[] memory);

    function vaultsLength() external view returns (uint256);

    function getVaults(
        TradeSide[] memory sides,
        OptionType[] memory optionTypes
    ) external view returns (Vault[] memory);

    function addVault(
        address vault,
        TradeSide side,
        OptionType optionType
    ) external;

    function removeVault(address vault) external;
}
