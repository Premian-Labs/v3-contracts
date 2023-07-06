// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {DualMiningStorage} from "./DualMiningStorage.sol";
import {IDualMining} from "./IDualMining.sol";

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
    function addRewards(UD60x18 amount) external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();
        IERC20(l.rewardToken).safeTransferFrom(msg.sender, address(this), amount.unwrap());
        l.rewardsAvailable = l.rewardsAvailable + amount;
    }

    function setRewardsPerYear(UD60x18 rewardsPerYear) external onlyOwner {
        DualMiningStorage.layout().rewardsPerYear = rewardsPerYear;
        emit SetRewardsPerYear(rewardsPerYear);
    }

    /// @inheritdoc IDualMining
    function updatePool() external {
        _updatePool(DualMiningStorage.layout());
    }

    function _updatePool(DualMiningStorage.Layout storage l) internal {
        if (block.timestamp <= l.lastRewardTimestamp) return;

        UD60x18 rewardAmount = _calculateRewardsUpdate(l);
        l.lastRewardTimestamp = block.timestamp;

        if (rewardAmount == ZERO) return;

        l.rewardsAvailable = l.rewardsAvailable - rewardAmount;
        l.accTotalRewards = l.accTotalRewards + rewardAmount;
    }

    /// @inheritdoc IDualMining
    function updateUser(address user, UD60x18 poolRewards, UD60x18 userRewards) external {
        if (msg.sender != VAULT_MINING) revert DualMining__NotAuthorized(msg.sender);

        DualMiningStorage.Layout storage l = DualMiningStorage.layout();
        _updatePool(l);

        IDualMining.UserInfo storage uInfo = l.userInfo[user];

        UD60x18 accTotalRewards = l.accTotalRewards + poolRewards;
        l.accTotalRewards = accTotalRewards;

        UD60x18 userRewardPercentage = userRewards / (accTotalRewards - uInfo.lastAccTotalRewards);
        uInfo.lastAccTotalRewards = accTotalRewards;

        UD60x18 userReward = (l.accParentTotalRewards - uInfo.lastAccParentTotalRewards) * userRewardPercentage;
        uInfo.reward = uInfo.reward + userReward;
        uInfo.lastAccParentTotalRewards = l.accParentTotalRewards;

        // ToDo : Event
    }

    /// @inheritdoc IDualMining
    function claim() external {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        UD60x18 reward = l.userInfo[msg.sender].reward;
        l.userInfo[msg.sender].reward = ZERO;

        uint256 rewardAmount = OptionMath.scaleDecimals(reward.unwrap(), 18, l.rewardTokenDecimals);
        IERC20(l.rewardToken).safeTransfer(msg.sender, rewardAmount);

        // ToDo : Event
    }

    function _calculateRewardsUpdate(DualMiningStorage.Layout storage l) internal view returns (UD60x18 rewardAmount) {
        UD60x18 yearsElapsed = ud((block.timestamp - l.lastRewardTimestamp) * WAD) / ud(365 days * WAD);
        rewardAmount = yearsElapsed * l.rewardsPerYear;

        // If we are running out of rewards to distribute, distribute whats left
        if (rewardAmount > l.rewardsAvailable) {
            rewardAmount = l.rewardsAvailable;
        }
    }
}
