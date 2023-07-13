// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

interface IUserSettings is IMulticall {
    /// @notice Enumeration representing different actions which `user` may authorize an `operator` to perform
    enum Action {
        __, // intentionally left blank to prevent 0 from being a valid action
        Annihilate,
        Exercise,
        Settle,
        SettlePosition,
        WriteFrom
    }

    error UserSettings__InvalidAction();
    error UserSettings__InvalidArrayLength();

    event ActionAuthorizationUpdated(
        address indexed user,
        address indexed operator,
        Action[] actions,
        bool[] authorization
    );

    event AuthorizedCostUpdated(address indexed user, UD60x18 amount);

    /// @notice Returns true if `operator` is authorized to perform `action` for `user`
    /// @param user The user who grants authorization
    /// @param operator The operator who is granted authorization
    /// @param action The action `operator` is authorized to perform
    /// @return True if `operator` is authorized to perform `action` for `user`
    function isActionAuthorized(address user, address operator, Action action) external view returns (bool);

    /// @notice Returns the actions and their corresponding authorization states. If the state of an action is true,
    ////        `operator` has been granted authorization by `user` to perform the action on their behalf. Note, the 0th
    ///         indexed enum in Action is omitted from `actions`.
    /// @param user The user who grants authorization
    /// @param operator The operator who is granted authorization
    /// @return actions All available actions a `user` may grant authorization to `operator` for
    /// @return authorization The authorization states of each `action`
    function getActionAuthorization(
        address user,
        address operator
    ) external view returns (Action[] memory actions, bool[] memory authorization);

    /// @notice Sets the authorization state for each action an `operator` may perform on behalf of `user`. `actions`
    ///         must be indexed in the same order as their corresponding `authorization` state.
    /// @param operator The operator who is granted authorization
    /// @param actions The actions to modify authorization state for
    /// @param authorization The authorization states to set for each action
    function setActionAuthorization(address operator, Action[] memory actions, bool[] memory authorization) external;

    /// @notice Returns the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, settleFor`, and `settlePositionFor`
    /// @return The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function getAuthorizedCost(address user) external view returns (UD60x18);

    /// @notice Sets the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, `settleFor`, and `settlePositionFor`
    /// @param amount The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function setAuthorizedCost(UD60x18 amount) external;
}
