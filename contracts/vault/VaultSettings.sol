// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IVaultSettings} from "./IVaultSettings.sol";
import {VaultSettingsStorage} from "./VaultSettingsStorage.sol";

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

contract VaultSettings is IVaultSettings, SafeOwnable {
    using VaultSettingsStorage for VaultSettingsStorage.Layout;

    function getSettings(
        bytes32 vaultType
    ) external view returns (bytes memory) {
        VaultSettingsStorage.Layout storage l = VaultSettingsStorage.layout();
        return l.settings[vaultType];
    }

    function updateSettings(
        bytes32 vaultType,
        bytes memory updatedSettings
    ) external onlyOwner {
        VaultSettingsStorage.Layout storage l = VaultSettingsStorage.layout();
        l.settings[vaultType] = updatedSettings;
    }
}
