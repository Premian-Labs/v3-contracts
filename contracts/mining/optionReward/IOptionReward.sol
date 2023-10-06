// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IOptionReward {
    error OptionReward__ClaimPeriodEnded(uint256 claimEnd);
    error OptionReward__ClaimPeriodNotEnded(uint256 claimEnd);
    error OptionReward__InvalidSettlement();
    error OptionReward__LockupNotExpired(uint256 lockupEnd);
    error OptionReward__NoBaseReserved(UD60x18 strike, uint256 maturity);
    error OptionReward__NoRedeemableLongs();
    error OptionReward__NotCallOption(address option);
    error OptionReward__UnderwriterNotAuthorized(address sender);
    error OptionReward__OptionNotExpired(uint256 maturity);
    error OptionReward__PriceIsZero();
    error OptionReward__ZeroRewardPerContract(UD60x18 strike, uint256 maturity);

    event Underwrite(address indexed longReceiver, UD60x18 strike, uint64 maturity, UD60x18 contractSize);
    event RewardsClaimed(
        address indexed user,
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize,
        UD60x18 baseAmount
    );
    event RewardsNotClaimedReleased(UD60x18 strike, uint64 maturity, UD60x18 baseAmount);
    event Settled(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize,
        UD60x18 intrinsicValuePerContract,
        UD60x18 maxRedeemableLongs,
        UD60x18 baseAmountPaid,
        UD60x18 baseAmountFee,
        UD60x18 quoteAmountPaid,
        UD60x18 quoteAmountFee,
        UD60x18 baseAmountReserved
    );

    struct SettleVarsInternal {
        UD60x18 intrinsicValuePerContract;
        UD60x18 rewardPerContract;
        UD60x18 totalUnderwritten;
        UD60x18 maxRedeemableLongs;
        UD60x18 baseAmountReserved;
        uint256 fee;
    }

    /// @notice Underwrite an option
    /// @param longReceiver the address that will receive the long tokens
    /// @param contractSize number of long tokens to mint (18 decimals)
    function underwrite(address longReceiver, UD60x18 contractSize) external;

    /// @notice Use expired longs to claim a percentage of expired option intrinsic value as reward,
    /// after `lockupDuration` has passed
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @return baseAmount the amount of base tokens earned as reward
    function claimRewards(UD60x18 strike, uint64 maturity) external returns (uint256 baseAmount);

    /// @notice Settle options after the exercise period has ended, reserve base tokens necessary for `claimRewards`,
    /// and transfer excess base tokens + quote tokens to `paymentSplitter`
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    function settle(UD60x18 strike, uint64 maturity) external;

    /// @notice Releases base tokens reserved for `claimRewards`,
    /// if rewards have not be claimed at `maturity + lockupDuration + claimDuration`
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    function releaseRewardsNotClaimed(UD60x18 strike, uint64 maturity) external;

    /// @notice Returns the amount of base tokens reserved for `claimRewards`
    function getTotalBaseReserved() external view returns (uint256);

    /// @notice Returns the max amount of expired longs that a user can use to claim rewards for a given option
    function getRedeemableLongs(address user, UD60x18 strike, uint64 maturity) external view returns (UD60x18);
}
