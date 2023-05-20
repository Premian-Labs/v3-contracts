// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

interface IVaultRegistry {
    // Enumerations
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

    // Structs
    struct Vault {
        address vault;
        bytes32 vaultType;
        TradeSide side;
        OptionType optionType;
    }

    // Events
    event VaultAdded(
        address indexed vault,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    );

    event VaultRemoved(address indexed vault);

    /// @notice Gets the total number of vaults in the registry.
    /// @return The total number of vaults in the registry.
    function getNumberOfVaults() external view returns (uint256);

    /// @notice Adds a vault to the registry.
    /// @param vault The proxy address of the vault.
    /// @param vaultType The type of the vault.
    /// @param side The trade side of the vault.
    /// @param optionType The option type of the vault.
    function addVault(
        address vault,
        bytes32 vaultType,
        TradeSide side,
        OptionType optionType
    ) external;

    /// @notice Removes a vault from the registry.
    /// @param vault The proxy address of the vault.
    function removeVault(address vault) external;

    /// @notice Returns whether the given address is a vault
    /// @param vault The address to check
    /// @return Whether the given address is a vault
    function isVault(address vault) external view returns (bool);

    /// @notice Gets the vault at the specified by the proxy address.
    /// @param vault The proxy address of the vault.
    /// @return The vault associated with the proxy address.
    function getVault(address vault) external view returns (Vault memory);

    /// @notice Gets all vaults in the registry.
    /// @return All vaults in the registry.
    function getVaults() external view returns (Vault[] memory);

    /// @notice Gets all vaults with trade side `side` and option type `optionType`.
    /// @param side The trade side.
    /// @param optionType The option type.
    /// @return All vaults with trade side `side` and option type `optionType`.
    function getVaultsByFilter(
        TradeSide side,
        OptionType optionType
    ) external view returns (Vault[] memory);

    /// @notice Gets all vaults with trade side `side`.
    /// @param side The trade side.
    /// @return All vaults with trade side `side`.
    function getVaultsByTradeSide(
        TradeSide side
    ) external view returns (Vault[] memory);

    /// @notice Gets all vaults with option type `optionType`.
    /// @param optionType The option type.
    /// @return All vaults with option type `optionType`.
    function getVaultsByOptionType(
        OptionType optionType
    ) external view returns (Vault[] memory);

    /// @notice Gets all the vaults of type `vaultType`.
    /// @param vaultType The vault type.
    /// @return All the vaults of type `vaultType`.
    function getVaultsByType(
        bytes32 vaultType
    ) external view returns (Vault[] memory);

    /// @notice Gets the settings for the vaultType.
    /// @param vaultType The vault type.
    /// @return The vault settings.
    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory);

    /// @notice Sets the implementation for the vaultType.
    /// @param vaultType The vault type.
    /// @param updatedSettings The updated settings for the vault type.
    function updateSettings(
        bytes32 vaultType,
        bytes memory updatedSettings
    ) external;

    /// @notice Gets the implementation for the vaultType.
    /// @param vaultType The vault type.
    /// @return The implementation address.
    function getImplementation(
        bytes32 vaultType
    ) external view returns (address);

    /// @notice Sets the implementation for the vaultType.
    /// @param vaultType The vault type.
    /// @param implementation The implementation contract address
    function setImplementation(
        bytes32 vaultType,
        address implementation
    ) external;
}
