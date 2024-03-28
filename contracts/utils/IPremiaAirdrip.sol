// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPremiaAirdrip {
    error PremiaAirdrip__ArrayEmpty();
    error PremiaAirdrip__Initialized();
    error PremiaAirdrip__InvalidUser(address user, UD60x18 influence);
    error PremiaAirdrip__InvalidVestingDates();
    error PremiaAirdrip__NotInitialized();
    error PremiaAirdrip__ZeroAmountClaimable();

    event Initialized(UD60x18 emissionRate, UD60x18 totalInfluence);
    event Claimed(address indexed user, uint256 amount, uint256 monthlyAllocation);

    struct User {
        address user;
        UD60x18 influence;
    }

    struct Allocation {
        uint256 amount;
        uint256 vestDate;
    }

    /// @notice Initializes the airdrip contract by pulling $PREMIA tokens from msg.sender and setting state variables
    /// @param users The users that will receive the premia tokens
    function initialize(address sender, User[] memory users) external;

    /// @notice Claims the premia tokens for the user.
    function claim() external;

    /// @notice Returns the vesting schedule for `user`
    /// @param user The address to get the vesting schedule for
    /// @return allocations The vesting schedule for `user`
    function previewVestingSchedule(address user) external view returns (Allocation[12] memory allocations);

    /// @notice Returns the claimed allocations for `user`
    /// @param user The address to get the claimed allocations for
    /// @return allocations The claimed allocations for `user`
    function previewClaimedAllocations(address user) external view returns (Allocation[12] memory allocations);

    /// @notice Returns the pending allocations for `user`
    /// @param user The address to get the pending allocations for
    /// @return allocations The pending allocations for `user`
    function previewPendingAllocations(address user) external view returns (Allocation[12] memory allocations);
}
