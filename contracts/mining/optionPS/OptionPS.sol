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
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {ZERO, ONE} from "../../libraries/Constants.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";

import {IOptionPS} from "./IOptionPS.sol";
import {OptionPSStorage} from "./OptionPSStorage.sol";

contract OptionPS is ERC1155Base, ERC1155Enumerable, ERC165Base, IOptionPS, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using OptionPSStorage for IERC20;
    using OptionPSStorage for int128;
    using OptionPSStorage for uint256;
    using OptionPSStorage for OptionPSStorage.Layout;
    using OptionPSStorage for TokenType;
    using SafeERC20 for IERC20;

    address internal immutable FEE_RECEIVER;
    UD60x18 internal constant FEE = UD60x18.wrap(0.003e18); // 0.3%

    // @notice amount of time the exercise period lasts (in seconds)
    uint256 internal constant EXERCISE_DURATION = 7 days;

    constructor(address feeReceiver) {
        FEE_RECEIVER = feeReceiver;
    }

    function getSettings() external view returns (address base, address quote, bool isCall) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        return (l.base, l.quote, l.isCall);
    }

    function getExerciseDuration() external pure returns (uint256) {
        return EXERCISE_DURATION;
    }

    /// @inheritdoc IOptionPS
    function underwrite(
        UD60x18 strike,
        uint64 maturity,
        address longReceiver,
        UD60x18 contractSize
    ) external nonReentrant {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        // Validate maturity
        if ((maturity % 24 hours) != 8 hours) revert OptionPS__OptionMaturityNot8UTC(maturity);

        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(strike);
        if (strike % strikeInterval != ZERO) revert OptionPS__StrikeNotMultipleOfStrikeInterval(strike, strikeInterval);

        IERC20(l.base).safeTransferFrom(msg.sender, address(this), l.toTokenDecimals(contractSize, true));

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(msg.sender, shortTokenId, contractSize);

        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] + contractSize;

        emit Underwrite(msg.sender, longReceiver, contractSize, strike, maturity);
    }

    /// @inheritdoc IOptionPS
    function annihilate(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfExercisePeriodEnded(maturity);

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] - contractSize;

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        _burnUD60x18(msg.sender, shortTokenId, contractSize);

        IERC20(l.base).safeTransfer(msg.sender, l.toTokenDecimals(contractSize, true));

        emit Annihilate(msg.sender, contractSize, strike, maturity);
    }

    /// @inheritdoc IOptionPS
    function exercise(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external nonReentrant returns (uint256 exerciseValue) {
        _revertIfOptionNotExpired(maturity);

        uint256 longTokenId = TokenType.LONG.formatTokenId(maturity, strike);

        UD60x18 _exerciseValue = contractSize;
        UD60x18 exerciseCost = strike * contractSize;

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        IERC20(l.quote).safeTransferFrom(msg.sender, address(this), l.toTokenDecimals(exerciseCost, false));

        UD60x18 fee = exerciseCost * FEE;
        IERC20(l.quote).safeTransfer(FEE_RECEIVER, l.toTokenDecimals(fee, false));

        l.totalExercised[strike][maturity] = l.totalExercised[strike][maturity] + contractSize;
        l.totalExerciseCost[strike][maturity] = l.totalExerciseCost[strike][maturity] + (exerciseCost - fee);

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        exerciseValue = l.toTokenDecimals(_exerciseValue, true);
        IERC20(l.base).safeTransfer(msg.sender, exerciseValue);

        emit Exercise(msg.sender, contractSize, _exerciseValue, exerciseCost, strike, maturity);
    }

    /// @inheritdoc IOptionPS
    function settle(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external nonReentrant returns (uint256 baseAmount, uint256 quoteAmount) {
        _revertIfExercisePeriodNotEnded(maturity);

        uint256 shortTokenId = TokenType.SHORT.formatTokenId(maturity, strike);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        UD60x18 totalUnderwritten = l.totalUnderwritten[strike][maturity];

        UD60x18 percentageExercised = l.totalExercised[strike][maturity] / totalUnderwritten;
        UD60x18 collateralLeft = contractSize * (ONE - percentageExercised);
        UD60x18 exerciseShare = l.totalExerciseCost[strike][maturity] * (contractSize / totalUnderwritten);

        _burnUD60x18(msg.sender, shortTokenId, contractSize);

        baseAmount = l.toTokenDecimals(contractSize, true);
        quoteAmount = l.toTokenDecimals(contractSize, false);
        IERC20(l.base).safeTransfer(msg.sender, baseAmount);
        IERC20(l.quote).safeTransfer(msg.sender, quoteAmount);

        emit Settle(msg.sender, contractSize, strike, maturity, collateralLeft, exerciseShare);
    }

    /// @inheritdoc IOptionPS
    function getTokenIds() external view returns (uint256[] memory) {
        return OptionPSStorage.layout().tokenIds.toArray();
    }

    /// @notice `_mint` wrapper, converts `UD60x18` to `uint256`
    function _mintUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _mint(account, tokenId, amount.unwrap(), "");
    }

    /// @notice `_burn` wrapper, converts `UD60x18` to `uint256`
    function _burnUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _burn(account, tokenId, amount.unwrap());
    }

    /// @notice Revert if option has not expired
    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionPS__OptionNotExpired(maturity);
    }

    /// @notice Revert if exercise period has not ended
    function _revertIfExercisePeriodNotEnded(uint64 maturity) internal view {
        uint256 target = maturity + EXERCISE_DURATION;
        if (block.timestamp < target) revert OptionPS__ExercisePeriodNotEnded(maturity, target);
    }

    function _revertIfExercisePeriodEnded(uint64 maturity) internal view {
        uint256 target = maturity + EXERCISE_DURATION;
        if (block.timestamp > target) revert OptionPS__ExercisePeriodEnded(maturity, target);
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

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids[i];

            if (amounts[i] == 0) continue;

            if (from == address(0)) {
                l.tokenIds.add(id);
            }

            if (to == address(0) && _totalSupply(id) == 0) {
                l.tokenIds.remove(id);
            }
        }
    }
}
