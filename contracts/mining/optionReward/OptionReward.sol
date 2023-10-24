// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "../../libraries/Constants.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {PRBMathExtra} from "../../libraries/PRBMathExtra.sol";

import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";

import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {OptionPSStorage} from "../optionPS/OptionPSStorage.sol";

import {IOptionReward} from "./IOptionReward.sol";
import {OptionRewardStorage} from "./OptionRewardStorage.sol";
import {IPaymentSplitter} from "../IPaymentSplitter.sol";

contract OptionReward is IOptionReward, ReentrancyGuard {
    using OptionRewardStorage for IERC20;
    using OptionRewardStorage for int128;
    using OptionRewardStorage for uint256;
    using OptionRewardStorage for OptionRewardStorage.Layout;
    using OptionPSStorage for IOptionPS.TokenType;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /// @inheritdoc IOptionReward
    function previewOptionParams() public view returns (UD60x18 strike, uint64 maturity) {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        // Calculates the maturity starting from the 8AM UTC timestamp of the current day
        maturity = (block.timestamp - (block.timestamp % 24 hours) + 8 hours + l.optionDuration).toUint64();
        UD60x18 price = l.oracleAdapter.getPrice(l.base, l.quote);
        _revertIfPriceIsZero(price);
        // Applies discount to spot price and rounds to nearest strike interval
        strike = OptionMath.roundToStrikeInterval(price * l.discount);
    }

    /// @inheritdoc IOptionReward
    function underwrite(address longReceiver, UD60x18 contractSize) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        uint256 collateral = l.toTokenDecimals(contractSize, true);
        IERC20(l.base).safeTransferFrom(msg.sender, address(this), collateral);
        IERC20(l.base).approve(address(l.option), collateral);

        (UD60x18 strike, uint64 maturity) = previewOptionParams();

        l.redeemableLongs[longReceiver][strike][maturity] =
            l.redeemableLongs[longReceiver][strike][maturity] +
            contractSize;

        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] + contractSize;
        l.option.underwrite(strike, maturity, longReceiver, contractSize);

        emit Underwrite(longReceiver, strike, maturity, contractSize);
    }

    /// @inheritdoc IOptionReward
    function claimRewards(UD60x18 strike, uint64 maturity) external nonReentrant returns (uint256 baseAmount) {
        _revertIfLockPeriodNotEnded(maturity);
        _revertIfClaimPeriodEnded(maturity);

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        UD60x18 redeemableLongs = l.redeemableLongs[msg.sender][strike][maturity];
        if (redeemableLongs == ZERO) revert OptionReward__NoRedeemableLongs();

        UD60x18 rewardPerContract = l.rewardPerContract[strike][maturity];
        if (rewardPerContract == ZERO) revert OptionReward__ZeroRewardPerContract(strike, maturity);

        uint256 longTokenId = IOptionPS.TokenType.Long.formatTokenId(maturity, strike);
        UD60x18 contractSize = ud(l.option.balanceOf(msg.sender, longTokenId));
        if (contractSize > redeemableLongs) {
            contractSize = redeemableLongs;
        }

        // Burn the longs of the users
        l.option.safeTransferFrom(msg.sender, BURN_ADDRESS, longTokenId, contractSize.unwrap(), "");
        l.redeemableLongs[msg.sender][strike][maturity] = redeemableLongs - contractSize;

        UD60x18 _baseAmount = rewardPerContract * contractSize;
        baseAmount = l.toTokenDecimals(_baseAmount, true);
        l.totalBaseReserved -= baseAmount;
        l.baseReserved[strike][maturity] -= baseAmount;

        IERC20(l.base).safeTransfer(msg.sender, baseAmount);

        emit RewardsClaimed(msg.sender, strike, maturity, contractSize, _baseAmount);
    }

    /// @inheritdoc IOptionReward
    function releaseRewardsNotClaimed(UD60x18 strike, uint64 maturity) external nonReentrant {
        _revertIfClaimPeriodNotEnded(maturity);

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        uint256 baseReserved = l.baseReserved[strike][maturity];

        if (baseReserved == 0) revert OptionReward__NoBaseReserved(strike, maturity);

        l.totalBaseReserved -= baseReserved;
        delete l.baseReserved[strike][maturity];

        IERC20(l.base).approve(address(l.paymentSplitter), baseReserved);
        l.paymentSplitter.pay(baseReserved, 0);

        emit RewardsNotClaimedReleased(strike, maturity, l.fromTokenDecimals(baseReserved, true));
    }

    /// @inheritdoc IOptionReward
    function getRewardPerContract(UD60x18 strike, uint64 maturity) external view returns (UD60x18) {
        return OptionRewardStorage.layout().rewardPerContract[strike][maturity];
    }

    /// @inheritdoc IOptionReward
    function settle(UD60x18 strike, uint64 maturity) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        _revertIfNotExpired(maturity);

        SettleVarsInternal memory vars;

        {
            UD60x18 price = l.oracleAdapter.getPriceAt(l.base, l.quote, maturity);
            _revertIfPriceIsZero(price);
            vars.intrinsicValuePerContract = strike > price ? ZERO : (price - strike) / price;
            vars.rewardPerContract = vars.intrinsicValuePerContract * (ONE - l.penalty);
            l.rewardPerContract[strike][maturity] = vars.rewardPerContract;
        }

        // We rely on `totalUnderwritten` rather than short balance, so that `settle` cant be call multiple times for
        // a same strike/maturity, by transferring shorts to it after a `settle` call
        vars.totalUnderwritten = l.totalUnderwritten[strike][maturity];
        if (vars.totalUnderwritten == ZERO) revert OptionReward__InvalidSettlement();
        l.totalUnderwritten[strike][maturity] = ZERO;

        {
            uint256 longTokenId = IOptionPS.TokenType.Long.formatTokenId(maturity, strike);
            UD60x18 longTotalSupply = ud(l.option.totalSupply(longTokenId));

            // Calculate the max amount of contracts for which the `claimRewards` can be called after the lockup period
            vars.maxRedeemableLongs = PRBMathExtra.min(vars.totalUnderwritten, longTotalSupply);
        }

        (, uint256 quoteAmount) = l.option.settleShort(strike, maturity, vars.totalUnderwritten);

        vars.fee = l.toTokenDecimals(l.fromTokenDecimals(quoteAmount, false) * l.fee, false);

        if (vars.fee > 0) IERC20(l.quote).safeTransfer(l.feeReceiver, vars.fee);
        IERC20(l.quote).approve(address(l.paymentSplitter), quoteAmount - vars.fee);

        // There is a possible scenario where, if other underwriters have underwritten the same strike/maturity,
        // directly on optionPS, and most of the long holders who purchased from other holder exercised, that settlement
        // would not return enough `base` tokens to cover the required amount that needs to be reserved,
        // and will return excess `quote` tokens instead.
        //
        // Though, this should be unlikely to happen in most case, as we are only reserving a percentage of the
        // intrinsic value of the option.
        // If this happens though, some excess `base` tokens from future settlements will be used to fill the
        // missing reserve amount.
        // As there is a lockup duration before tokens can be claimed, this should not be an issue, as there should be
        // more than enough time for any missing amount to be covered through excess `base` of future settlements.
        // Though if there was still for some reason a shortage of `base` tokens, we could transfer some `base` tokens
        // from liquidity mining fund to cover the missing amount.
        vars.baseAmountReserved = vars.maxRedeemableLongs * vars.rewardPerContract;
        l.totalBaseReserved = l.totalBaseReserved + l.toTokenDecimals(vars.baseAmountReserved, true);
        l.baseReserved[strike][maturity] = l.toTokenDecimals(vars.baseAmountReserved, true);

        uint256 baseAmountToPay;
        {
            uint256 baseBalance = IERC20(l.base).balanceOf(address(this));
            if (baseBalance > l.totalBaseReserved) {
                baseAmountToPay = baseBalance - l.totalBaseReserved;
            }
        }
        IERC20(l.base).approve(address(l.paymentSplitter), baseAmountToPay);

        l.paymentSplitter.pay(baseAmountToPay, quoteAmount - vars.fee);

        emit Settled(
            strike,
            maturity,
            vars.totalUnderwritten,
            vars.intrinsicValuePerContract,
            vars.maxRedeemableLongs,
            l.fromTokenDecimals(baseAmountToPay, true),
            ud(0),
            l.fromTokenDecimals(quoteAmount - vars.fee, false),
            l.fromTokenDecimals(vars.fee, false),
            vars.baseAmountReserved
        );
    }

    /// @inheritdoc IOptionReward
    function getTotalBaseReserved() external view returns (uint256) {
        return OptionRewardStorage.layout().totalBaseReserved;
    }

    /// @inheritdoc IOptionReward
    function getRedeemableLongs(address user, UD60x18 strike, uint64 maturity) external view returns (UD60x18) {
        return OptionRewardStorage.layout().redeemableLongs[user][strike][maturity];
    }

    /// @inheritdoc IOptionReward
    function getSettings()
        external
        view
        returns (
            IOptionPS option,
            IOracleAdapter oracleAdapter,
            IPaymentSplitter paymentSplitter,
            UD60x18 discount,
            UD60x18 penalty,
            uint256 optionDuration,
            uint256 lockupDuration,
            uint256 claimDuration,
            UD60x18 fee,
            address feeReceiver
        )
    {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        return (
            l.option,
            l.oracleAdapter,
            l.paymentSplitter,
            l.discount,
            l.penalty,
            l.optionDuration,
            l.lockupDuration,
            l.claimDuration,
            l.fee,
            l.feeReceiver
        );
    }

    /// @notice Revert if price is zero
    function _revertIfPriceIsZero(UD60x18 price) internal pure {
        if (price == ZERO) revert OptionReward__PriceIsZero();
    }

    /// @notice Revert if lock period has not ended
    function _revertIfLockPeriodNotEnded(uint64 maturity) internal view {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        if (block.timestamp < maturity + l.lockupDuration)
            revert OptionReward__LockupNotExpired(maturity + l.lockupDuration);
    }

    /// @notice Revert if claim period has not ended
    function _revertIfClaimPeriodEnded(uint64 maturity) internal view {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        if (block.timestamp > maturity + l.lockupDuration + l.claimDuration)
            revert OptionReward__ClaimPeriodEnded(maturity + l.lockupDuration + l.claimDuration);
    }

    /// @notice Revert if claim period has not ended
    function _revertIfClaimPeriodNotEnded(uint64 maturity) internal view {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        if (block.timestamp < maturity + l.lockupDuration + l.claimDuration)
            revert OptionReward__ClaimPeriodNotEnded(maturity + l.lockupDuration + l.claimDuration);
    }

    /// @notice Revert if the option is not expired
    function _revertIfNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionReward__OptionNotExpired(maturity);
    }
}
