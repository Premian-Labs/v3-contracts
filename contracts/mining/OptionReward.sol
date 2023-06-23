// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";
import {ERC1155Base} from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";
import {ERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseInternal.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ZERO, ONE} from "../libraries/Constants.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

import {IOptionReward} from "./IOptionReward.sol";
import {IPaymentSplitter} from "./IPaymentSplitter.sol";
import {IPriceRepository} from "./IPriceRepository.sol";
import {OptionRewardStorage} from "./OptionRewardStorage.sol";

contract OptionReward is ERC1155Base, ERC1155Enumerable, ERC165Base, IOptionReward, ReentrancyGuard {
    using OptionRewardStorage for IERC20;
    using OptionRewardStorage for int128;
    using OptionRewardStorage for uint256;
    using OptionRewardStorage for OptionRewardStorage.Layout;
    using OptionRewardStorage for TokenType;
    using SafeCast for uint256;

    address public immutable TREASURY;
    UD60x18 public immutable TREASURY_FEE;

    uint256 public constant STALE_PRICE_THRESHOLD = 24 hours;

    constructor(address treasury, UD60x18 treasuryFee) {
        TREASURY = treasury;
        TREASURY_FEE = treasuryFee;
    }

    /// @inheritdoc IOptionReward
    function writeFrom(address longReceiver, UD60x18 contractSize) external nonReentrant {
        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();
        if (msg.sender != l.underwriter) revert OptionReward__UnderwriterNotAuthorized(msg.sender);

        IERC20(l.base).safeTransferFromUD60x18(l.underwriter, address(this), l.toTokenDecimals(contractSize, true));

        // Calculates the maturity starting from the 8AM UTC timestamp of the current day
        uint64 maturity = (block.timestamp - (block.timestamp % 24 hours) + 8 hours + l.expiryDuration).toUint64();

        (UD60x18 price, uint256 timestamp) = IPriceRepository(l.priceRepository).getPrice(l.base, l.quote);

        _revertIfPriceIsStale(timestamp);
        _revertIfPriceIsZero(price);

        UD60x18 strike = OptionMath.roundToStrikeInterval(price * l.discount);
        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(l.underwriter, shortTokenId, contractSize);

        emit WriteFrom(l.underwriter, longReceiver, contractSize, strike, maturity);
    }

    /// @inheritdoc IOptionReward
    function exercise(uint256 longTokenId, UD60x18 contractSize) external nonReentrant {
        (TokenType tokenType, uint64 maturity, int128 _strike) = longTokenId.parseTokenId();
        if (tokenType != TokenType.LONG) revert OptionReward__TokenTypeNotLong();

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        uint256 lockupStart = maturity + l.exerciseDuration;
        uint256 lockupEnd = lockupStart + l.lockupDuration;

        _revertIfOptionNotExpired(maturity);
        _revertIfLockupNotExpired(lockupStart, lockupEnd);

        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
        _revertIfPriceIsZero(settlementPrice);

        UD60x18 strike = _strike.fromInt128ToUD60x18();
        if (settlementPrice < strike) revert OptionReward__OptionOutTheMoney(settlementPrice, strike);

        // If the option is in-the-money during the exercise period, the position is physically settled.
        UD60x18 exerciseValue = contractSize;
        UD60x18 exerciseCost = l.toTokenDecimals(strike * contractSize, false);

        if (block.timestamp >= lockupEnd) {
            // If the option is exercised after the lockup period, the option is cash settled with a penalty.
            UD60x18 intrinsicValue = settlementPrice - strike;

            exerciseValue = (intrinsicValue * contractSize) / settlementPrice;
            exerciseValue = exerciseValue * (ONE - l.penalty);

            IERC20(l.base).safeTransferUD60x18(l.underwriter, l.toTokenDecimals(contractSize - exerciseValue, true));
            exerciseCost = ZERO;
        }

        if (exerciseCost > ZERO) {
            IERC20(l.quote).safeTransferFromUD60x18(msg.sender, address(this), exerciseCost);

            UD60x18 fee = exerciseCost * TREASURY_FEE;
            IERC20(l.quote).safeTransferUD60x18(TREASURY, fee);

            uint256 rewardAmount = (exerciseCost - fee).unwrap();
            IERC20(l.quote).approve(l.paymentSplitter, rewardAmount);
            IPaymentSplitter(l.paymentSplitter).addReward(rewardAmount);
        }

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(msg.sender, l.toTokenDecimals(exerciseValue, true));

        emit Exercise(msg.sender, contractSize, exerciseValue, exerciseCost, settlementPrice, strike, maturity);
    }

    /// @inheritdoc IOptionReward
    function settle(uint256 shortTokenId, UD60x18 contractSize) external nonReentrant {
        (TokenType tokenType, uint64 maturity, int128 _strike) = shortTokenId.parseTokenId();
        if (tokenType != TokenType.SHORT) revert OptionReward__TokenTypeNotShort();

        _revertIfOptionNotExpired(maturity);

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
        _revertIfPriceIsZero(settlementPrice);

        UD60x18 strike = _strike.fromInt128ToUD60x18();
        if (settlementPrice >= strike) revert OptionReward__OptionInTheMoney(settlementPrice, strike);

        _burnUD60x18(l.underwriter, shortTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(l.underwriter, l.toTokenDecimals(contractSize, true));

        emit Settle(l.underwriter, contractSize, settlementPrice, strike, maturity);
    }

    /// @notice `_mint` wrapper, converts `UD60x18` to `uint256`
    function _mintUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _mint(account, tokenId, amount.unwrap(), "");
    }

    /// @notice `_burn` wrapper, converts `UD60x18` to `uint256`
    function _burnUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _burn(account, tokenId, amount.unwrap());
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

    /// @notice Revert if option has not expired
    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionReward__OptionNotExpired(maturity);
    }

    /// @notice Revert if lockup period has not expired
    function _revertIfLockupNotExpired(uint256 lockupStart, uint256 lockupEnd) internal view {
        if (block.timestamp >= lockupStart && block.timestamp < lockupEnd)
            revert OptionReward__LockupNotExpired(lockupStart, lockupEnd);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155BaseInternal, ERC1155EnumerableInternal) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
