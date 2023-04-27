// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IUserSettings} from "./IUserSettings.sol";
import {UserSettingsStorage} from "./UserSettingsStorage.sol";

contract UserSettings is IUserSettings {
    /// @inheritdoc IUserSettings
    function getAuthorizedAgents(
        address user
    ) external view returns (address[] memory) {
        return UserSettingsStorage.layout().authorizedAgents[user];
    }

    /// @inheritdoc IUserSettings
    function setAuthorizedAgents(address[] memory agents) external {
        UserSettingsStorage.layout().authorizedAgents[msg.sender] = agents;
    }

    /// @inheritdoc IUserSettings
    function getAuthorizedCost(address user) external view returns (uint256) {
        return UserSettingsStorage.layout().authorizedCost[user];
    }

    /// @inheritdoc IUserSettings
    function setAuthorizedCost(uint256 amount) external {
        UserSettingsStorage.layout().authorizedCost[msg.sender] = amount;
    }
}
