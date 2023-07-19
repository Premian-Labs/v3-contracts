// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IVaultMining {
    error VaultMining__NotVault(address caller);

    event Claim(address indexed user, address indexed vault, UD60x18 rewardAmount);

    event UpdateVaultVotes(address indexed vault, UD60x18 votes, UD60x18 vaultUtilisationRate);

    event SetRewardsPerYear(UD60x18 rewardsPerYear);

    //

    struct VaultInfo {
        // Total shares for this vault
        UD60x18 totalShares;
        // Amount of votes for this vault
        UD60x18 votes;
        // Last timestamp at which distribution occurred
        uint256 lastRewardTimestamp;
        // Accumulated rewards per share
        UD60x18 accRewardsPerShare;
    }

    struct UserInfo {
        // User shares
        UD60x18 shares;
        // Total allocated unclaimed rewards
        UD60x18 reward;
        // Reward debt. See explanation below
        UD60x18 rewardDebt;
        //   pending reward = (user.shares * vault.accPremiaPerShare) - user.rewardDebt
        //
        // Whenever a user vault shares change. Here's what happens:
        //   1. The vault's `accPremiaPerShare` (and `lastRewardTimestamp`) gets updated.
        //   2. User allocated `reward` is updated
        //   3. User's `shares` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct VaultVotes {
        address vault;
        UD60x18 votes;
        UD60x18 vaultUtilisationRate;
    }

    /// @notice Add rewards to the contract
    function addRewards(UD60x18 amount) external;

    /// @notice Return amount of rewards not yet allocated
    function getRewardsAvailable() external view returns (UD60x18);

    /// @notice Return amount of pending rewards (not yet claimed) for a user, on a specific vault
    function getPendingUserRewards(address user, address vault) external view returns (UD60x18);

    /// @notice Return the total amount of votes across all vaults (Used to calculate share of rewards allocation for each vault)
    function getTotalVotes() external view returns (UD60x18);

    /// @notice Return internal variables for a vault
    function getVaultInfo(address vault) external view returns (VaultInfo memory);

    /// @notice Return internal variables for a user, on a specific vault
    function getUserInfo(address user, address vault) external view returns (UserInfo memory);

    /// @notice Get the amount of rewards emitted per year
    function getRewardsPerYear() external view returns (UD60x18);

    /// @notice Claim rewards for a list of vaults
    function claim(address[] memory vaults) external;

    /// @notice Trigger an update for a user on a specific vault
    /// This needs to be called by the vault, anytime the user's shares change
    /// Can only be called by a vault registered on the VaultRegistry
    /// @param user The user to update
    /// @param vault The vault for which to update
    /// @param newUserShares The new amount of shares for the user
    /// @param newTotalShares The new amount of total shares for the vault
    /// @param utilisationRate The new utilisation rate for the vault
    function updateUser(
        address user,
        address vault,
        UD60x18 newUserShares,
        UD60x18 newTotalShares,
        UD60x18 utilisationRate
    ) external;

    /// @notice Trigger an update for a vault
    function updateVault(address vault) external;

    /// @notice Trigger an update for all vaults
    function updateVaults() external;

    /// @notice Trigger an update for a user on a specific vault
    function updateUser(address user, address vault) external;
}
