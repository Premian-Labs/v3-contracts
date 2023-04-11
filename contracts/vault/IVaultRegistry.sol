// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

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
        bytes32 vaultType;
        TradeSide side;
        OptionType optionType;
    }

    // Events
    event VaultAdded(
        address indexed vault,
        TradeSide side,
        OptionType optionType
    );

    event VaultRemoved(address indexed vault);

    function getNumberOfVaults() external view returns (uint256);

    function addVault(
        address vault,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external;

    function removeVault(address vault) external;

    function getVaultAddressAt(uint256 index) external view returns (address);

    function getVault(
        address vaultAddress
    ) external view returns (Vault memory);

    function getVaults() external view returns (Vault[] memory);

    function getVaults(
        TradeSide[] memory sides,
        OptionType[] memory optionTypes
    ) external view returns (Vault[] memory);

    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory);

    function updateSettings(
        bytes32 vaultType,
        bytes memory updatedSettings
    ) external;

    function getImplementation(
        bytes32 vaultType
    ) external view returns (address);

    function setImplementation(
        bytes32 vaultType,
        address implementation
    ) external;
}
