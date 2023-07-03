// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IReentrancyGuardExtended {
    event ReentrancyStaticCallCheck();
    event SetReentrancyGuardDisabled(bool disabled);

    /// @notice Sets the reentrancy guard disabled override state
    function setReentrancyGuardDisabled(bool disabled) external;
}
