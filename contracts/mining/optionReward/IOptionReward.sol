// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IOptionReward {
    error OptionReward__LockupNotExpired(uint256 lockupEnd);
    error OptionReward__NotCallOption(address option);
    error OptionReward__NotEnoughRedeemableLongs(UD60x18 redeemableLongs, UD60x18 amount);
    error OptionReward__UnderwriterNotAuthorized(address sender);
    error OptionReward__ExercisePeriodNotEnded(uint256 maturity, uint256 exercisePeriodEnd);
    error OptionReward__OptionNotExpired(uint256 maturity);
    error OptionReward__OptionInTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error OptionReward__OptionOutTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error OptionReward__PriceIsStale(uint256 blockTimestamp, uint256 timestamp);
    error OptionReward__PriceIsZero();

    function underwrite(UD60x18 contractSize) external;

    function claimRewards(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    function settle(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;
}
