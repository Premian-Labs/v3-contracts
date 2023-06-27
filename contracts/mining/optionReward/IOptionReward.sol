// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IOptionReward {
    error OptionReward__LockupNotExpired(uint256 lockupStart, uint256 lockupEnd);
    error OptionReward__NotCallOption(address option);
    error OptionReward__UnderwriterNotAuthorized(address sender);
    error OptionReward__OptionNotExpired(uint256 maturity);
    error OptionReward__OptionInTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error OptionReward__OptionOutTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error OptionReward__PriceIsStale(uint256 blockTimestamp, uint256 timestamp);
    error OptionReward__PriceIsZero();

    function underwrite(UD60x18 contractSize) external;

    function redeem(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    function claimRewards(UD60x18 strike, uint64 maturity) external;
}
