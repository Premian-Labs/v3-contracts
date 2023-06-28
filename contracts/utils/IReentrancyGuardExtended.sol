// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

interface IReentrancyGuardExtended {
    event AddReentrancyGuardSelectorIgnored(bytes4 selector);
    event ReentrancyStaticCallCheck();
    event RemoveReentrancyGuardSelectorIgnored(bytes4 selector);
    event SetReentrancyGuardDisabled(bool disabled);

    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external;

    function setReentrancyGuardDisabled(bool disabled) external;
}
