// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "../../libraries/Constants.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";

import {IOptionPhysicallySettled} from "../optionPhysicallySettled/IOptionPhysicallySettled.sol";
import {OptionPhysicallySettledStorage} from "../optionPhysicallySettled/OptionPhysicallySettledStorage.sol";

import {IOptionReward} from "./IOptionReward.sol";

import {OptionRewardStorage} from "./OptionRewardStorage.sol";
import {IPaymentSplitter} from "../IPaymentSplitter.sol";
import {IPriceRepository} from "../IPriceRepository.sol";

contract OptionReward is IOptionReward, ReentrancyGuard {
    using OptionRewardStorage for IERC20;
    using OptionRewardStorage for int128;
    using OptionRewardStorage for uint256;
    using OptionRewardStorage for OptionRewardStorage.Layout;
    using OptionPhysicallySettledStorage for IOptionPhysicallySettled.TokenType;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    address public immutable TREASURY;
    UD60x18 public immutable TREASURY_FEE;

    uint256 public constant STALE_PRICE_THRESHOLD = 24 hours;

    constructor(address treasury, UD60x18 treasuryFee) {
        TREASURY = treasury;
        TREASURY_FEE = treasuryFee;
    }

    function underwrite(UD60x18 contractSize) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        uint256 collateral = l.toTokenDecimals(contractSize, true);
        IERC20(l.base).safeTransferFrom(l.underwriter, address(this), collateral);
        IERC20(l.base).approve(address(l.option), collateral);

        // Calculates the maturity starting from the 8AM UTC timestamp of the current day
        uint64 maturity = (block.timestamp - (block.timestamp % 24 hours) + 8 hours + l.expiryDuration).toUint64();

        (UD60x18 price, uint256 timestamp) = IPriceRepository(l.priceRepository).getPrice(l.base, l.quote);

        _revertIfPriceIsStale(timestamp);
        _revertIfPriceIsZero(price);

        // ToDo : Check this
        UD60x18 strike = OptionMath.roundToStrikeInterval(price * l.discount);

        l.option.underwrite(strike, maturity, msg.sender, contractSize);

        // ToDo : Add event
    }

    /// @notice Give up the right to exercise the option, and receive a percentage of the intrinsic value of the option,
    /// unlocked after the lockup period
    function redeem(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        uint256 longTokenId = IOptionPhysicallySettled.TokenType.LONG.formatTokenId(maturity, strike);
        l.option.safeTransferFrom(msg.sender, address(this), longTokenId, contractSize.unwrap(), "");
        l.option.annihilate(strike, maturity, contractSize);

        l.redeemed[msg.sender][strike][maturity] = l.redeemed[msg.sender][strike][maturity] + contractSize;

        // ToDo : Add event
    }

    /// @notice Claim rewards from longs "redeemed" after the lockup period
    function claimRewards(UD60x18 strike, uint64 maturity) external nonReentrant {
        // ToDo : Implement
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
}
