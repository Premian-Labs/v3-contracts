// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "../../libraries/Constants.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";
import {PRBMathExtra} from "../../libraries/PRBMathExtra.sol";

import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {OptionPSStorage} from "../optionPS/OptionPSStorage.sol";

import {IOptionReward} from "./IOptionReward.sol";

import {OptionRewardStorage} from "./OptionRewardStorage.sol";
import {IPaymentSplitter} from "../IPaymentSplitter.sol";
import {IPriceRepository} from "../IPriceRepository.sol";

contract OptionReward is IOptionReward, ReentrancyGuard {
    using OptionRewardStorage for IERC20;
    using OptionRewardStorage for int128;
    using OptionRewardStorage for uint256;
    using OptionRewardStorage for OptionRewardStorage.Layout;
    using OptionPSStorage for IOptionPS.TokenType;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    address internal constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public immutable FEE_RECEIVER;
    UD60x18 public immutable FEE;

    uint256 public constant STALE_PRICE_THRESHOLD = 24 hours;

    constructor(address feeReceiver, UD60x18 fee) {
        FEE_RECEIVER = feeReceiver;
        FEE = fee;
    }

    function claimOption(UD60x18 contractSize) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        uint256 collateral = l.toTokenDecimals(contractSize, true);
        IERC20(l.base).safeTransferFrom(l.underwriter, address(this), collateral);
        IERC20(l.base).approve(address(l.option), collateral);

        // Calculates the maturity starting from the 8AM UTC timestamp of the current day
        uint64 maturity = (block.timestamp - (block.timestamp % 24 hours) + 8 hours + l.expiryDuration).toUint64();

        (UD60x18 price, uint256 timestamp) = IPriceRepository(l.priceRepository).getPrice(l.base, l.quote);

        _revertIfPriceIsStale(timestamp);
        _revertIfPriceIsZero(price);

        UD60x18 strike = OptionMath.roundToStrikeInterval(price * l.discount);

        l.redeemableLongs[msg.sender][strike][maturity] =
            l.redeemableLongs[msg.sender][strike][maturity] +
            contractSize;
        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] + contractSize;
        l.option.underwrite(strike, maturity, msg.sender, contractSize);

        emit OptionClaimed(msg.sender, contractSize);
    }

    /// @notice Claim rewards from longs "redeemed" after the lockup period
    function claimRewards(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfLockPeriodNotEnded(maturity);

        uint256 longTokenId = IOptionPS.TokenType.LONG.formatTokenId(maturity, strike);

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        UD60x18 redeemableLongs = l.redeemableLongs[msg.sender][strike][maturity];
        if (contractSize > redeemableLongs)
            revert OptionReward__NotEnoughRedeemableLongs(redeemableLongs, contractSize);

        // Burn the longs of the users
        l.option.safeTransferFrom(msg.sender, BURN_ADDRESS, longTokenId, contractSize.unwrap(), "");
        l.redeemableLongs[msg.sender][strike][maturity] = redeemableLongs - contractSize;

        UD60x18 baseAmount = l.intrinsicValuePerContract[strike][maturity] * contractSize;
        uint256 _baseAmount = l.toTokenDecimals(baseAmount, true);
        l.totalBaseAllocated -= _baseAmount;

        IERC20(l.base).safeTransfer(msg.sender, _baseAmount);

        emit RewardsClaimed(msg.sender, strike, maturity, contractSize, baseAmount);
    }

    function settle(UD60x18 strike, uint64 maturity) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        _revertIfExercisePeriodNotEnded(l, maturity);

        SettleVarsInternal memory vars;

        {
            UD60x18 price = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
            _revertIfPriceIsZero(price);
            vars.intrinsicValuePerContract = strike > price ? ZERO : (price - strike) / price;
            l.intrinsicValuePerContract[strike][maturity] = vars.intrinsicValuePerContract;
        }

        // We rely on `totalUnderwritten` rather than short balance, so that `settle` cant be call multiple times for
        // a same strike/maturity, by transferring shorts to it after a `settle` call
        vars.totalUnderwritten = l.totalUnderwritten[strike][maturity];
        if (vars.totalUnderwritten == ZERO) revert OptionReward__InvalidSettlement();
        l.totalUnderwritten[strike][maturity] = ZERO;

        {
            uint256 longTokenId = IOptionPS.TokenType.LONG.formatTokenId(maturity, strike);
            UD60x18 longTotalSupply = ud(l.option.totalSupply(longTokenId));

            // Calculate the max amount of contracts for which the `claimRewards` can be called after the lockup period
            vars.maxRedeemableLongs = PRBMathExtra.min(vars.totalUnderwritten, longTotalSupply);
        }

        (, uint256 quoteAmount) = l.option.settle(strike, maturity, vars.totalUnderwritten);

        vars.fee = l.toTokenDecimals(l.fromTokenDecimals(quoteAmount, false) * FEE, false);
        IERC20(l.quote).safeTransfer(FEE_RECEIVER, vars.fee);
        IERC20(l.quote).approve(l.paymentSplitter, quoteAmount - vars.fee);

        vars.baseAmountReserved = vars.maxRedeemableLongs * vars.intrinsicValuePerContract * (ONE - l.penalty);

        l.totalBaseAllocated = l.totalBaseAllocated + l.toTokenDecimals(vars.baseAmountReserved, true);

        uint256 baseAmountToPay;
        {
            uint256 baseBalance = IERC20(l.base).balanceOf(address(this));
            if (baseBalance > l.totalBaseAllocated) {
                baseAmountToPay = baseBalance - l.totalBaseAllocated;
            }
        }

        IPaymentSplitter(l.paymentSplitter).pay(baseAmountToPay, quoteAmount - vars.fee);

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

    function getTotalBaseAllocated() external view returns (uint256) {
        return OptionRewardStorage.layout().totalBaseAllocated;
    }

    /// @notice Revert if price is stale
    function _revertIfPriceIsStale(uint256 timestamp) internal view {
        if (block.timestamp - timestamp >= STALE_PRICE_THRESHOLD)
            revert OptionReward__PriceIsStale(block.timestamp, timestamp);
    }

    /// @notice Revert if price is zero
    function _revertIfPriceIsZero(UD60x18 price) internal pure {
        if (price == ZERO) revert OptionReward__PriceIsZero();
    }

    /// @notice Revert if exercise period has not ended
    function _revertIfLockPeriodNotEnded(uint64 maturity) internal view {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        if (block.timestamp < maturity + l.lockupDuration)
            revert OptionReward__LockupNotExpired(maturity + l.lockupDuration);
    }

    /// @notice Revert if exercise period has not ended
    function _revertIfExercisePeriodNotEnded(OptionRewardStorage.Layout storage l, uint64 maturity) internal view {
        uint256 target = maturity + l.option.getExerciseDuration();
        if (block.timestamp < target) revert OptionReward__ExercisePeriodNotEnded(maturity, target);
    }
}
