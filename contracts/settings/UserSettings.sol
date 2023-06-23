// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {IUserSettings} from "./IUserSettings.sol";
import {UserSettingsStorage} from "./UserSettingsStorage.sol";

contract UserSettings is IUserSettings, Multicall {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @inheritdoc IUserSettings
    function isAuthorized(address user, address operator, Authorization authorization) external view returns (bool) {
        return UserSettingsStorage.layout().authorizations[user][operator].contains(uint256(authorization));
    }

    /// @inheritdoc IUserSettings
    function getAuthorizations(
        address user,
        address operator
    ) external view returns (Authorization[] memory, bool[] memory) {
        uint256 length = uint256(type(Authorization).max) + 1;
        Authorization[] memory authorizations = new Authorization[](length);
        bool[] memory authorized = new bool[](length);

        UserSettingsStorage.Layout storage l = UserSettingsStorage.layout();
        for (uint256 i = 0; i < length; i++) {
            authorizations[i] = Authorization(i);
            authorized[i] = l.authorizations[user][operator].contains(i);
        }

        return (authorizations, authorized);
    }

    /// @inheritdoc IUserSettings
    function setAuthorizations(
        address operator,
        Authorization[] memory authorizations,
        bool[] memory authorize
    ) external {
        if (authorizations.length != authorize.length) revert UserSettings__InvalidArrayLength();

        UserSettingsStorage.Layout storage l = UserSettingsStorage.layout();
        EnumerableSet.UintSet storage _authorizations = l.authorizations[msg.sender][operator];

        for (uint256 i = 0; i < authorizations.length; i++) {
            uint256 authorization = uint256(authorizations[i]);
            authorize[i] ? _authorizations.add(authorization) : _authorizations.remove(authorization);
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
