// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IMulticall} from "@solidstate/contracts/utils/IMulticall.sol";

interface IUserSettings is IMulticall {
    /// @notice Returns true if the agent is authorized to call `exerciseFor`, `settleFor`, or `settlePositionFor` on
    ///         behalf of the user
    /// @param user The user who has authorized the agent
    /// @param agent The agent who is authorized by the user
    /// @return True if the agent is authorized to call `exerciseFor`, `settleFor`, or `settlePositionFor`
    function isAuthorizedAgent(address user, address agent) external view returns (bool);

    /// @notice Returns the addresses of agents authorized to call `exerciseFor`, `settleFor`, or `settlePositionFor`
    ///         on behalf of the user
    /// @param user The user who has authorized agents
    /// @return The addresses of authorized agents
    function getAuthorizedAgents(address user) external view returns (address[] memory);

    /// @notice Sets the addresses authorized to call `exerciseFor`, `settleFor`, or `settlePositionFor` on behalf of
    ///         the user
    /// @param agents The addresses of authorized agents
    function setAuthorizedAgents(address[] memory agents) external;

    /// @notice Returns the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, settleFor`, and `settlePositionFor`
    /// @return The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function getAuthorizedCost(address user) external view returns (uint256);

    /// @notice Sets the users authorized cost in the ERC20 Native token (WETH, WFTM, etc) used in conjunction with
    ///         `exerciseFor`, `settleFor`, and `settlePositionFor`
    /// @param amount The users authorized cost in the ERC20 Native token (WETH, WFTM, etc) (18 decimals)
    function setAuthorizedCost(uint256 amount) external;

    /// @notice Sets whether the given operator is authorized or not to call `annihilateFor` on behalf of the user
    /// @param operator The operator who is authorized or not
    /// @param isAuthorized True if the operator is authorized, false otherwise
    function setAuthorizedAnnihilate(address operator, bool isAuthorized) external;

    /// @notice Returns the addresses of operators authorized to call `annihilateFor` on behalf of the user
    /// @param user The user from which to get authorized operators
    /// @return The addresses of authorized operators
    function getAuthorizedAnnihilate(address user) external view returns (address[] memory);

    /// @notice Returns true if the operator is authorized to call `annihilateFor` on behalf of the user
    /// @param user The user for which to check if the operator is authorized
    /// @param operator The operator to check if authorized
    function isAuthorizedAnnihilate(address user, address operator) external view returns (bool);
}
