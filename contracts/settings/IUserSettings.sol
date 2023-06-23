// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

interface IUserSettings is IMulticall {
    /// @notice Enumeration representing different functions which `operator` may or may not be authorized to perform
    enum Authorization {
        ANNIHILATE,
        EXERCISE,
        SETTLE,
        SETTLE_POSITION,
        WRITE_FROM
    }

    error UserSettings__InvalidArrayLength();

    /// @notice Returns true if `operator` is authorized to perform the function `authorization` for `user`
    /// @param user The user who has authorization
    /// @param operator The operator may or may not be granted authorization
    /// @param authorization The function `operator` may or may not be authorized to perform
    /// @return True if `operator` is authorized to perform the function `authorization` for `user`
    function isAuthorized(address user, address operator, Authorization authorization) external view returns (bool);

    /// @notice Returns the available functions `operator` may or may not be authorized to perform for `user`
    /// @param user The user who has authorization
    /// @param operator The operator may or may not be granted authorization
    /// @return The functions `user` may enable or disable authorization for
    /// @return The states of authorization for each function in `authorizations`
    function getAuthorizations(
        address user,
        address operator
    ) external view returns (Authorization[] memory, bool[] memory);

    /// @notice Sets the authorization for `operator` to perform the functions in `authorizations` for caller
    /// @param operator The operator may or may not be granted authorization
    /// @param authorizations The functions caller may enable or disable authorization for
    /// @param authorize The states of authorization to set for each function in `authorizations`
    function setAuthorizations(
        address operator,
        Authorization[] memory authorizations,
        bool[] memory authorize
    ) external;

    /// @notice Returns the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, settleFor`, and `settlePositionFor`
    /// @return The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function getAuthorizedCost(address user) external view returns (uint256);

    /// @notice Sets the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, `settleFor`, and `settlePositionFor`
    /// @param amount The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function setAuthorizedCost(uint256 amount) external;
}
