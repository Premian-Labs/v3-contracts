// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IUserSettings {
    function getAuthorizedAgents(
        address user
    ) external view returns (address[] memory);

    function setAuthorizedAgents(address[] memory agents) external;

    function getAuthorizedTxCostAndFee(
        address user
    ) external view returns (uint256);

    function setAuthorizedTxCostAndFee(uint256 amount) external;
}
