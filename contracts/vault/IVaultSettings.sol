// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

interface IVaultSettings {
    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory);

    function updateSettings(
        bytes32 vaultType,
        bytes memory updatedSettings
    ) external;
}
