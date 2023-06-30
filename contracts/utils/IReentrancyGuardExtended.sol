// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

interface IReentrancyGuardExtended {
    event AddReentrancyGuardSelectorIgnored(bytes4 selector);
    event ReentrancyStaticCallCheck();
    event RemoveReentrancyGuardSelectorIgnored(bytes4 selector);
    event SetReentrancyGuardDisabled(bool disabled);

    /// @notice Returns the list of selectors that are ignored by the reentrancy guard
    /// @return selectorsIgnored The list of selectors that are ignored by the reentrancy guard
    function getReentrancyGuardSelectorsIgnored() external view returns (bytes4[] memory selectorsIgnored);

    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    function setReentrancyGuardDisabled(bool disabled) external;
}
