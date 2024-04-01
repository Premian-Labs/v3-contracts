// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPremiaAirdrip {
    error PremiaAirdrip__ArrayEmpty();
    error PremiaAirdrip__Initialized();
    error PremiaAirdrip__InvalidUser(address user, UD60x18 influence);
    error PremiaAirdrip__NotClaimable(uint256 lastClaim, uint256 blockTimestamp);
    error PremiaAirdrip__NotInitialized();
    error PremiaAirdrip__NotVested(uint256 vestingStart, uint256 blockTimestamp);
    error PremiaAirdrip__ZeroAmountClaimable();

    event Initialized(UD60x18 premiaPerInfluence, UD60x18 totalInfluence);
    event Claimed(address indexed user, uint256 amount, uint256 totalClaimed, uint256 totalRemaining);

    struct User {
        address addr;
        UD60x18 influence;
    }

    /// @notice Initializes the airdrip contract by pulling $PREMIA tokens from msg.sender and setting state variables
    /// @param users The users that will receive the premia tokens
    function initialize(User[] memory users) external;

    /// @notice Claims the premia tokens for the user.
    function claim() external;

    /// @notice Returns the max amount claimable (throughout entire vesting period)
    /// @param user The user to check
    /// @return The max claimable amount
    function previewMaxClaimableAmount(address user) external view returns (uint256);

    /// @notice Returns the amount claimable since the last claim was made (or the vesting start)
    /// @param user The user to check
    /// @return The claimable amount
    function previewClaimableAmount(address user) external view returns (uint256);

    /// @notice Returns the remaining amount claimable (throughout entire vesting period)
    /// @param user The user to check
    /// @return The remaining claimable amount
    function previewClaimRemaining(address user) external view returns (uint256);

    /// @notice Returns the amount claimed
    /// @param user The user to check
    /// @return The claimed amount
    function previewClaimedAmount(address user) external view returns (uint256);
}
