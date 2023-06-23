// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {IUserSettings} from "./IUserSettings.sol";
import {UserSettingsStorage} from "./UserSettingsStorage.sol";

contract UserSettings is IUserSettings, Multicall {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @inheritdoc IUserSettings
    function isActionAuthorized(address user, address operator, Action action) external view returns (bool) {
        return UserSettingsStorage.layout().authorizedActions[user][operator].contains(uint256(action));
    }

    /// @inheritdoc IUserSettings
    function getActionAuthorization(
        address user,
        address operator
    ) external view returns (Action[] memory, bool[] memory) {
        uint256 length = uint256(type(Action).max);
        Action[] memory actions = new Action[](length);
        bool[] memory authorization = new bool[](length);

        UserSettingsStorage.Layout storage l = UserSettingsStorage.layout();
        for (uint256 i = 0; i < length; i++) {
            uint256 action = i + 1; // skip enum 0
            actions[i] = Action(action);
            authorization[i] = l.authorizedActions[user][operator].contains(action);
        }

        return (actions, authorization);
    }

    /// @inheritdoc IUserSettings
    function setActionAuthorization(address operator, Action[] memory actions, bool[] memory authorization) external {
        if (actions.length != authorization.length) revert UserSettings__InvalidArrayLength();

        UserSettingsStorage.Layout storage l = UserSettingsStorage.layout();
        EnumerableSet.UintSet storage authorizedActions = l.authorizedActions[msg.sender][operator];

        for (uint256 i = 0; i < actions.length; i++) {
            Action action = actions[i];
            if (action == Action.__) revert UserSettings__InvalidAction();
            authorization[i] ? authorizedActions.add(uint256(action)) : authorizedActions.remove(uint256(action));
        }

        emit ActionAuthorizationUpdated(msg.sender, operator, actions, authorization);
    }

    /// @inheritdoc IUserSettings
    function getAuthorizedCost(address user) external view returns (uint256) {
        return UserSettingsStorage.layout().authorizedCost[user];
    }

    /// @inheritdoc IUserSettings
    function setAuthorizedCost(uint256 amount) external {
        UserSettingsStorage.layout().authorizedCost[msg.sender] = amount;
        emit AuthorizedCostUpdated(msg.sender, amount);
    }
}
