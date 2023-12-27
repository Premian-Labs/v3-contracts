// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IRewardDistributor} from "./IRewardDistributor.sol";

contract RewardDistributor is IRewardDistributor, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address internal immutable REWARD_TOKEN;

    mapping(address => uint256) public rewards;

    constructor(address rewardToken) {
        REWARD_TOKEN = rewardToken;
    }

    function addRewards(address[] calldata users, uint256[] calldata amounts) external nonReentrant {
        if (users.length != amounts.length) revert RewardDistributor__InvalidArrayLength();

        uint256 totalRewards;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalRewards += amounts[i];
        }

        IERC20(REWARD_TOKEN).safeTransferFrom(msg.sender, address(this), totalRewards);

        for (uint256 i = 0; i < users.length; i++) {
            rewards[users[i]] += amounts[i];
            emit AddedRewards(msg.sender, users[i], amounts[i]);
        }
    }

    function claim() external nonReentrant {
        uint256 reward = rewards[msg.sender];
        if (reward == 0) revert RewardDistributor__NoRewards();

        delete rewards[msg.sender];

        IERC20(REWARD_TOKEN).safeTransfer(msg.sender, reward);

        emit Claimed(msg.sender, reward);
    }
}
