// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IUserSettings {
    /// @notice Returns the addresses of authorized agents used in conjunction with `exerciseFor`, `settleFor`,
    ///         and `settlePositionFor`
    /// @param user The user who has authorized agents
    /// @return The addresses of authorized agents
    function getAuthorizedAgents(
        address user
    ) external view returns (address[] memory);

    /// @notice Sets the addresses of authorized agents used in conjunction with `exerciseFor`, `settleFor`,
    ///         and `settlePositionFor`
    /// @param agents The addresses of authorized agents
    function setAuthorizedAgents(address[] memory agents) external;

    /// @notice Returns the users authorized cost in the Wrapped Native Asset used in conjunction with `exerciseFor`,
    ///         `settleFor`, and `settlePositionFor`
    /// @return The users authorized cost in the Wrapped Native Asset (18 decimals)
    function getAuthorizedCost(address user) external view returns (uint256);

    /// @notice Sets the users authorized cost in the Wrapped Native Asset used in conjunction with `exerciseFor`,
    ///         `settleFor`, and `settlePositionFor`
    /// @param amount The users authorized cost in the Wrapped Native Asset (18 decimals)
    function setAuthorizedCost(uint256 amount) external;
}
