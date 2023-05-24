// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {IUserSettings} from "./IUserSettings.sol";
import {UserSettingsStorage} from "./UserSettingsStorage.sol";

contract UserSettings is IUserSettings {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IUserSettings
    function isAuthorizedAgent(address user, address agent) external view returns (bool) {
        return UserSettingsStorage.layout().authorizedAgents[user].contains(agent);
    }

    /// @inheritdoc IUserSettings
    function getAuthorizedAgents(address user) external view returns (address[] memory) {
        return UserSettingsStorage.layout().authorizedAgents[user].toArray();
    }

    /// @inheritdoc IUserSettings
    function setAuthorizedAgents(address[] memory agents) external {
        EnumerableSet.AddressSet storage _agents = UserSettingsStorage.layout().authorizedAgents[msg.sender];

        for (uint256 i = 0; i < agents.length; i++) {
            _agents.add(agents[i]);
        }
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
