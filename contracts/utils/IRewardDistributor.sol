// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IRewardDistributor {
    error RewardDistributor__InvalidArrayLength();
    error RewardDistributor__NoRewards();

    event AddedRewards(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    function addRewards(address[] calldata users, uint256[] calldata amounts) external;

    function claim() external;
}
