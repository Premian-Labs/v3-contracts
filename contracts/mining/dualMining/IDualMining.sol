// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IDualMining {
    error DualMining__AlreadyInitialized();
    error DualMining__NoMiningRewards();
    error DualMining__NotAuthorized(address caller);
    error DualMining__NotInitialized();
    error DualMining__MiningEnded();

    event Initialized(address indexed caller, UD60x18 initialParentAccRewardsPerShare, uint256 timestamp);
    event Claim(address indexed user, UD60x18 rewardAmount);
    event MiningEnded(UD60x18 finalParentAccRewardsPerShare);

    struct UserInfo {
        uint256 lastUpdateTimestamp;
        // `accParentTotalRewards` value at last user update
        UD60x18 lastParentAccTotalRewards;
        // `accTotalRewards` value at last user update
        UD60x18 lastAccTotalRewards;
        // Total allocated unclaimed rewards
        UD60x18 reward;
    }

    /// @notice Initialize dual mining. Can only be called by `VAULT_MINING` contract
    function init(UD60x18 initialParentAccRewardsPerShare) external;

    /// @notice Add rewards to the contract
    function addRewards(UD60x18 amount) external;

    /// @notice Return amount of rewards not yet allocated
    function getRewardsAvailable() external view returns (UD60x18);

    /// @notice Trigger an update for this mining pool. Can only be called by `VAULT_MINING` contract
    function updatePool(UD60x18 poolRewards, UD60x18 accRewardsPerShare) external;

    /// @notice Trigger an update for a specific user. Can only be called by `VAULT_MINING` contract
    function updateUser(
        address user,
        UD60x18 oldShares,
        UD60x18 oldRewardDebt,
        UD60x18 poolRewards,
        UD60x18 userRewards,
        UD60x18 accRewardsPerShare
    ) external;

    /// @notice Claim rewards
    function claim() external;
}
