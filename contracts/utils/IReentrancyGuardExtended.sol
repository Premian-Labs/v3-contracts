// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IReentrancyGuardExtended {
    event AddReentrancyGuardSelectorIgnored(bytes4 selector);
    event ReentrancyStaticCallCheck();
    event RemoveReentrancyGuardSelectorIgnored(bytes4 selector);
    event SetReentrancyGuardDisabled(bool disabled);

    /// @notice Returns the list of selectors that are ignored by the reentrancy guard
    /// @return selectorsIgnored The list of selectors that are ignored by the reentrancy guard
    function getReentrancyGuardSelectorsIgnored() external view returns (bytes4[] memory selectorsIgnored);

    /// @notice Adds selectors to the list of selectors that are ignored by the reentrancy guard
    /// @param selectorsIgnored The selectors to add
    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    /// @notice Removes selectors from the list of selectors that are ignored by the reentrancy guard
    /// @param selectorsIgnored The selectors to remove
    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    /// @notice Sets the reentrancy guard disabled override state
    function setReentrancyGuardDisabled(bool disabled) external;
}
