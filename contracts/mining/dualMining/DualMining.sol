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

    address internal VAULT_MINING;

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
    }

    /// @inheritdoc IDualMining
    function addRewards(UD60x18 amount) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        _revertIfMiningEnded(l);

        IERC20(l.rewardToken).safeTransferFrom(msg.sender, address(this), amount.unwrap());
        l.rewardsAvailable = l.rewardsAvailable + amount;
    }

    /// @inheritdoc IDualMining
    function updatePool(UD60x18 poolRewards, UD60x18 accRewardsPerShare) external {
        _revertIfNotVaultMining(msg.sender);

        _updatePool(DualMiningStorage.layout(), poolRewards, accRewardsPerShare);
    }

    function _updatePool(DualMiningStorage.Layout storage l, UD60x18 poolRewards, UD60x18 accRewardsPerShare) internal {
        _revertIfNotInitialized(l);

        if (block.timestamp <= l.lastRewardTimestamp) return;
        if (l.finalParentAccRewardsPerShare > ZERO) return;

        if (poolRewards > ZERO) {
            l.parentAccTotalRewards = l.parentAccTotalRewards + poolRewards;
        }

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);
        l.lastRewardTimestamp = block.timestamp;

        if (rewardAmount == ZERO) return;

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
        UD60x18 poolRewards,
        UD60x18 userRewards,
        UD60x18 accRewardsPerShare
    ) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        _revertIfNotVaultMining(msg.sender);
        _revertIfNotInitialized(l);

        IDualMining.UserInfo storage uInfo = l.userInfo[user];

        UD60x18 toSubtract;
        if (uInfo.lastUpdateTimestamp < l.startTimestamp) {
            toSubtract = oldShares * l.initialParentAccRewardsPerShare - oldRewardDebt;
        }

        if (l.finalParentAccRewardsPerShare > ZERO) {
            toSubtract = toSubtract + (oldShares * l.finalParentAccRewardsPerShare) - oldRewardDebt;
        }

        _updatePool(l, poolRewards, accRewardsPerShare);

        UD60x18 userRewardPercentage = (userRewards - toSubtract) /
            (l.parentAccTotalRewards - uInfo.lastParentAccTotalRewards);
        uInfo.lastParentAccTotalRewards = l.parentAccTotalRewards;

        UD60x18 userReward = (l.accTotalRewards - uInfo.lastAccTotalRewards) * userRewardPercentage;
        uInfo.reward = uInfo.reward + userReward;
        uInfo.lastAccTotalRewards = l.accTotalRewards;
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
