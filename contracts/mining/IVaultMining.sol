// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IVaultMining {
    event Claim(address indexed user, address indexed vault, UD60x18 rewardAmount);

    event UpdateVaultVotes(address indexed vault, uint256 votes, UD60x18 vaultUtilizationRate);

    //

    struct VaultInfo {
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
        // We do some fancy math here. Basically, any point in time, the amount of rewards
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * vault.accPremiaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a vault. Here's what happens:
        //   1. The vault's `accPremiaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct VaultVotes {
        address vault;
        UD60x18 votes;
        UD60x18 vaultUtilizationRate;
    }
}
