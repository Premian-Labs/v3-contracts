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

import {IOptionPhysicallySettled} from "./IOptionPhysicallySettled.sol";
import {IPaymentSplitter} from "./IPaymentSplitter.sol";
import {IPriceRepository} from "./IPriceRepository.sol";
import {OptionPhysicallySettledStorage} from "./OptionPhysicallySettledStorage.sol";

contract OptionPhysicallySettled is
    ERC1155Base,
    ERC1155Enumerable,
    ERC165Base,
    IOptionPhysicallySettled,
    ReentrancyGuard
{
    using OptionPhysicallySettledStorage for IERC20;
    using OptionPhysicallySettledStorage for int128;
    using OptionPhysicallySettledStorage for uint256;
    using OptionPhysicallySettledStorage for OptionPhysicallySettledStorage.Layout;
    using OptionPhysicallySettledStorage for TokenType;
    using SafeCast for uint256;

    address public immutable TREASURY;
    UD60x18 public immutable TREASURY_FEE;

    uint256 public constant STALE_PRICE_THRESHOLD = 25 hours;

    constructor(address treasury, UD60x18 treasuryFee) {
        TREASURY = treasury;
        TREASURY_FEE = treasuryFee;
    }

    /// @inheritdoc IOptionPhysicallySettled
    function underwrite(
        UD60x18 strike,
        uint64 maturity,
        address longReceiver,
        UD60x18 contractSize
    ) external nonReentrant {
        OptionPhysicallySettledStorage.Layout storage l = OptionPhysicallySettledStorage.layout();

        // Validate maturity
        if ((maturity % 24 hours) != 8 hours) revert OptionPhysicallySettled__OptionMaturityNot8UTC(maturity);

        // Validate strike
        (UD60x18 price, uint256 timestamp) = IPriceRepository(l.priceRepository).getPrice(l.base, l.quote);
        _revertIfPriceIsStale(timestamp);

        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(price);
        if (strike % strikeInterval != ZERO)
            revert OptionPhysicallySettled__StrikeNotMultipleOfStrikeInterval(strike, strikeInterval);

        IERC20(l.base).safeTransferFromUD60x18(msg.sender, address(this), l.toTokenDecimals(contractSize, true));

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(msg.sender, shortTokenId, contractSize);

        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] + contractSize;

        emit Underwrite(msg.sender, longReceiver, contractSize, strike, maturity);
    }

    /// @inheritdoc IOptionPhysicallySettled
    function annihilate(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        OptionPhysicallySettledStorage.Layout storage l = OptionPhysicallySettledStorage.layout();

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] - contractSize;

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        _burnUD60x18(msg.sender, shortTokenId, contractSize);

        IERC20(l.base).safeTransferUD60x18(msg.sender, contractSize);

        emit Annihilate(msg.sender, contractSize, strike, maturity);
    }

    /// @inheritdoc IOptionPhysicallySettled
    function exercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfOptionNotExpired(maturity);

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);

        OptionPhysicallySettledStorage.Layout storage l = OptionPhysicallySettledStorage.layout();

        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
        _revertIfPriceIsZero(settlementPrice);
        if (settlementPrice < strike) revert OptionPhysicallySettled__OptionOutTheMoney(settlementPrice, strike);

        UD60x18 exerciseValue = contractSize;
        UD60x18 exerciseCost = l.toTokenDecimals(strike * contractSize, false);

        IERC20(l.quote).safeTransferFromUD60x18(msg.sender, address(this), exerciseCost);

        UD60x18 fee = exerciseCost * TREASURY_FEE;
        IERC20(l.quote).safeTransferUD60x18(TREASURY, fee);

        l.totalExercised[strike][maturity] = l.totalExercised[strike][maturity] + contractSize;
        l.totalExerciseCost[strike][maturity] = l.totalExerciseCost[strike][maturity] + (exerciseCost - fee);

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(msg.sender, l.toTokenDecimals(exerciseValue, true));

        emit Exercise(msg.sender, contractSize, exerciseValue, exerciseCost, settlementPrice, strike, maturity);
    }

    /// @inheritdoc IOptionPhysicallySettled
    function settle(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        OptionPhysicallySettledStorage.Layout storage l = OptionPhysicallySettledStorage.layout();
        _revertIfExercisePeriodNotEnded(maturity + uint64(l.exerciseDuration));

        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        UD60x18 totalUnderwritten = l.totalUnderwritten[strike][maturity];

        UD60x18 percentageExercised = l.totalExercised[strike][maturity] / totalUnderwritten;
        UD60x18 collateralLeft = contractSize * (ONE - percentageExercised);
        UD60x18 exerciseShare = l.totalExerciseCost[strike][maturity] * (contractSize / totalUnderwritten);

        _burnUD60x18(msg.sender, shortTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(msg.sender, l.toTokenDecimals(contractSize, true));
        IERC20(l.quote).safeTransferUD60x18(msg.sender, l.toTokenDecimals(contractSize, true));

        emit Settle(msg.sender, contractSize, strike, maturity, collateralLeft, exerciseShare);
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
            revert OptionPhysicallySettled__PriceIsStale(block.timestamp, timestamp);
    }

    /// @notice Revert if price is zero
    function _revertIfPriceIsZero(UD60x18 price) internal pure {
        if (price == ZERO) revert OptionPhysicallySettled__PriceIsZero();
    }

    /// @notice Revert if option has not expired
    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionPhysicallySettled__OptionNotExpired(maturity);
    }

    /// @notice Revert if exercise period has not ended
    function _revertIfExercisePeriodNotEnded(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionPhysicallySettled__ExercisePeriodNotEnded(maturity);
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
