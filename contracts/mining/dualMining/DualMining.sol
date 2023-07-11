// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {DualMiningStorage} from "./DualMiningStorage.sol";
import {IDualMining} from "./IDualMining.sol";

import {IVaultMining} from "../vaultMining/IVaultMining.sol";

import {OptionMath} from "../../libraries/OptionMath.sol";
import {WAD, ZERO} from "../../libraries/Constants.sol";

contract DualMining is IDualMining, OwnableInternal {
    using DualMiningStorage for DualMiningStorage.Layout;
    using SafeERC20 for IERC20;

    address internal immutable VAULT_MINING;

    constructor(address vaultMining) {
        VAULT_MINING = vaultMining;
    }

    /// @inheritdoc IDualMining
    function init(UD60x18 initialParentAccRewardsPerShare) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        _revertIfNoMiningRewards(l);
        _revertIfNotVaultMining(msg.sender);
        _revertIfInitialized(l);

        l.initialParentAccRewardsPerShare = initialParentAccRewardsPerShare;
        l.startTimestamp = block.timestamp;
        l.lastRewardTimestamp = block.timestamp;

        emit Initialized(msg.sender, initialParentAccRewardsPerShare, block.timestamp);
    }

    /// @inheritdoc IDualMining
    function addRewards(UD60x18 amount) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        _revertIfMiningEnded(l);

        IERC20(l.rewardToken).safeTransferFrom(msg.sender, address(this), amount.unwrap());
        l.rewardsAvailable = l.rewardsAvailable + amount;
    }

    /// @inheritdoc IDualMining
    function getRewardsAvailable() external view returns (UD60x18) {
        return DualMiningStorage.layout().rewardsAvailable;
    }

    /// @inheritdoc IDualMining
    function updatePool(UD60x18 poolRewards, UD60x18 accRewardsPerShare) external {
        _revertIfNotVaultMining(msg.sender);

        _updatePool(DualMiningStorage.layout(), poolRewards, accRewardsPerShare);
    }

    function _updatePool(
        DualMiningStorage.Layout storage l,
        UD60x18 parentPoolRewards,
        UD60x18 accRewardsPerShare
    ) internal {
        _revertIfNotInitialized(l);

        // Already up to date
        if (block.timestamp <= l.lastRewardTimestamp) return;
        // Mining ended
        if (l.finalParentAccRewardsPerShare > ZERO) return;

        l.parentAccTotalRewards = l.parentAccTotalRewards + parentPoolRewards;

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);
        l.lastRewardTimestamp = block.timestamp;

        l.rewardsAvailable = l.rewardsAvailable - rewardAmount;
        l.accTotalRewards = l.accTotalRewards + rewardAmount;

        // Reward distribution ended
        if (l.rewardsAvailable == ZERO) {
            l.finalParentAccRewardsPerShare = accRewardsPerShare;
            emit MiningEnded(accRewardsPerShare);
        }
    }

    /// @inheritdoc IDualMining
    function updateUser(
        address user,
        UD60x18 oldShares,
        UD60x18 oldRewardDebt,
        UD60x18 parentPoolRewards,
        UD60x18 parentUserRewards,
        UD60x18 accRewardsPerShare
    ) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        _revertIfNotVaultMining(msg.sender);
        _revertIfNotInitialized(l);

        IDualMining.UserInfo storage uInfo = l.userInfo[user];

        // Mining is ended and user already had final update, so we can return
        if (
            l.finalParentAccRewardsPerShare > ZERO && uInfo.lastParentAccTotalRewards != l.finalParentAccRewardsPerShare
        ) return;

        UD60x18 toSubtract = _calculateUserRewardToSubtract(l, uInfo, oldShares, oldRewardDebt);
        _updatePool(l, parentPoolRewards, accRewardsPerShare);

        UD60x18 parentAccTotalRewardsSinceLastUpdate = l.parentAccTotalRewards - uInfo.lastParentAccTotalRewards;
        uInfo.lastParentAccTotalRewards = l.parentAccTotalRewards;

        if (parentAccTotalRewardsSinceLastUpdate > ZERO) {
            UD60x18 userRewardPercentage = (parentUserRewards - toSubtract) / parentAccTotalRewardsSinceLastUpdate;
            UD60x18 userReward = (l.accTotalRewards - uInfo.lastAccTotalRewards) * userRewardPercentage;
            uInfo.reward = uInfo.reward + userReward;
        }

        uInfo.lastAccTotalRewards = l.accTotalRewards;
        uInfo.lastUpdateTimestamp = block.timestamp;
    }

    /// @notice Calculate user reward accumulated in parent contract before the start of the emission in this contract.
    function _calculateUserRewardToSubtract(
        DualMiningStorage.Layout storage l,
        IDualMining.UserInfo storage uInfo,
        UD60x18 oldShares,
        UD60x18 oldRewardDebt
    ) internal view returns (UD60x18) {
        UD60x18 toSubtract;
        if (uInfo.lastUpdateTimestamp < l.startTimestamp) {
            // This calculates the amount of rewards the user mined in parent contract,
            // from his last update until the start of mining in this contract
            toSubtract = oldShares * l.initialParentAccRewardsPerShare - oldRewardDebt;
        }

        if (
            l.finalParentAccRewardsPerShare > ZERO && uInfo.lastParentAccTotalRewards != l.finalParentAccRewardsPerShare
        ) {
            // This calculates the amount of rewards the user mined in parent contract,
            // from end of mining in this contract until now
            toSubtract = toSubtract + (oldShares * l.finalParentAccRewardsPerShare) - oldRewardDebt;
        }

        return toSubtract;
    }

    /// @inheritdoc IDualMining
    function claim() external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();
        _revertIfNotInitialized(l);

        UD60x18 reward = l.userInfo[msg.sender].reward;
        l.userInfo[msg.sender].reward = ZERO;

        uint256 rewardAmount = OptionMath.scaleDecimals(reward.unwrap(), 18, l.rewardTokenDecimals);
        IERC20(l.rewardToken).safeTransfer(msg.sender, rewardAmount);

        emit Claim(msg.sender, reward);
    }

    /// @inheritdoc IDualMining
    function getPendingUserRewards(address user) external view returns (UD60x18) {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();
        IVaultMining.UserInfo memory uInfoParent = IVaultMining(VAULT_MINING).getUserInfo(user, l.vault);
        IDualMining.UserInfo storage uInfo = l.userInfo[user];

        UD60x18 userReward = uInfo.reward;
        UD60x18 toSubtract = _calculateUserRewardToSubtract(l, uInfo, uInfoParent.shares, uInfoParent.rewardDebt);

        // Calculate pending rewards not yet allocated globally
        UD60x18 accTotalRewards = l.accTotalRewards;
        UD60x18 parentAccTotalRewards = l.parentAccTotalRewards;
        if (block.timestamp > l.lastRewardTimestamp && l.finalParentAccRewardsPerShare == ZERO) {
            parentAccTotalRewards = parentAccTotalRewards + IVaultMining(VAULT_MINING).getPendingVaultRewards(l.vault);
            accTotalRewards = accTotalRewards + _calculateRewardsUpdate(l);
        }

        UD60x18 parentAccTotalRewardsSinceLastUpdate = l.parentAccTotalRewards - uInfo.lastParentAccTotalRewards;

        // Calculate user pending rewards not yet allocated
        if (parentAccTotalRewardsSinceLastUpdate > ZERO) {
            // We need to subtract `reward` here as we just want the amount corresponding to the rewards pending and not yet allocated to the user
            UD60x18 userNonAllocatedRewardsParent = IVaultMining(VAULT_MINING).getPendingUserRewards(user, l.vault) -
                uInfoParent.reward;

            UD60x18 userRewardPercentage = (userNonAllocatedRewardsParent - toSubtract) /
                parentAccTotalRewardsSinceLastUpdate;
            userReward = userReward + (accTotalRewards - uInfo.lastAccTotalRewards) * userRewardPercentage;
        }

        return userReward;
    }

    /// @inheritdoc IDualMining
    function getUserInfo(address user) external view returns (UserInfo memory) {
        return DualMiningStorage.layout().userInfo[user];
    }

    function _calculateRewardsUpdate(DualMiningStorage.Layout storage l) internal view returns (UD60x18 rewardAmount) {
        UD60x18 yearsElapsed = ud((block.timestamp - l.lastRewardTimestamp) * WAD) / ud(365 days * WAD);
        rewardAmount = yearsElapsed * l.rewardsPerYear;

        // If we are running out of rewards to distribute, distribute whats left
        if (rewardAmount > l.rewardsAvailable) {
            rewardAmount = l.rewardsAvailable;
        }
    }

    function _revertIfNotVaultMining(address caller) internal view {
        if (caller != VAULT_MINING) revert DualMining__NotAuthorized(msg.sender);
    }

    function _revertIfNotInitialized(DualMiningStorage.Layout storage l) internal view {
        if (l.startTimestamp == 0) revert DualMining__NotInitialized();
    }

    function _revertIfInitialized(DualMiningStorage.Layout storage l) internal view {
        if (l.startTimestamp > 0) revert DualMining__AlreadyInitialized();
    }

    function _revertIfMiningEnded(DualMiningStorage.Layout storage l) internal view {
        if (l.finalParentAccRewardsPerShare > ZERO) revert DualMining__MiningEnded();
    }

    function _revertIfNoMiningRewards(DualMiningStorage.Layout storage l) internal view {
        if (l.rewardsAvailable == ZERO) revert DualMining__NoMiningRewards();
    }
}
