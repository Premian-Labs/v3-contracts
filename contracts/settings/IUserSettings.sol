// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IUserSettings {
    /// @notice Returns the addresses of authorized agents
    /// @param user The user who has authorized agents
    /// @return The addresses of authorized agents
    function getAuthorizedAgents(
        address user
    ) external view returns (address[] memory);

    /// @notice Sets the addresses of authorized agents
    /// @param agents The addresses of authorized agents
    function setAuthorizedAgents(address[] memory agents) external;

    /// @notice Returns the users authorized total cost (tx cost + fee) in the Wrapped Native Asset (18 decimals)
    /// @param user The user who has authorized the total cost
    /// @return The users authorized total cost (tx cost + fee) in the Wrapped Native Asset (18 decimals)
    function getAuthorizedTxCostAndFee(
        address user
    ) external view returns (uint256);

    /// @notice Sets the users authorized total cost (tx cost + fee) in the Wrapped Native Asset (18 decimals)
    /// @param amount The users authorized total cost (tx cost + fee) in the Wrapped Native Asset (18 decimals)
    function setAuthorizedTxCostAndFee(uint256 amount) external;
}
