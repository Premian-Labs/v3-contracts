// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";
import {ERC1155Base} from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";
import {ERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseInternal.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
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

    constructor(address feeReceiver) {
        FEE_RECEIVER = feeReceiver;
    }

    /// @inheritdoc IOptionPS
    function name() external view returns (string memory) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        return string(abi.encodePacked("Option Physically Settled", " - ", _symbol(l)));
    }

    /// @inheritdoc IOptionPS
    function symbol() external view returns (string memory) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        return string(abi.encodePacked("PS-", _symbol(l)));
    }

    function _symbol(OptionPSStorage.Layout storage l) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    IERC20Metadata(l.base).symbol(),
                    "/",
                    IERC20Metadata(l.quote).symbol(),
                    "-",
                    l.isCall ? "C" : "P"
                )
            );
    }

    /// @inheritdoc IOptionPS
    function getSettings() external view returns (address base, address quote, bool isCall) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        return (l.base, l.quote, l.isCall);
    }

    /// @inheritdoc IOptionPS
    function underwrite(
        UD60x18 strike,
        uint64 maturity,
        address longReceiver,
        UD60x18 contractSize
    ) external nonReentrant {
        _revertIfOptionExpired(maturity);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        // Validate maturity
        if (!OptionMath.is8AMUTC(maturity)) revert OptionPS__OptionMaturityNot8UTC(maturity);

        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(strike);
        if (strike % strikeInterval != ZERO) revert OptionPS__StrikeNotMultipleOfStrikeInterval(strike, strikeInterval);

        address collateral = l.getCollateral();
        IERC20(collateral).safeTransferFrom(
            msg.sender,
            address(this),
            l.toTokenDecimals(l.isCall ? contractSize : contractSize * strike, collateral)
        );

        uint256 longTokenId = TokenType.Long.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.Short.formatTokenId(maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(msg.sender, shortTokenId, contractSize);

        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] + contractSize;

        emit Underwrite(msg.sender, longReceiver, strike, maturity, contractSize);
    }

    /// @inheritdoc IOptionPS
    function annihilate(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfOptionExpired(maturity);

        uint256 longTokenId = TokenType.Long.formatTokenId(maturity, strike);
        uint256 shortTokenId = TokenType.Short.formatTokenId(maturity, strike);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        l.totalUnderwritten[strike][maturity] = l.totalUnderwritten[strike][maturity] - contractSize;

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        _burnUD60x18(msg.sender, shortTokenId, contractSize);

        address collateral = l.getCollateral();
        IERC20(collateral).safeTransfer(
            msg.sender,
            l.toTokenDecimals(l.isCall ? contractSize : contractSize * strike, collateral)
        );

        emit Annihilate(msg.sender, strike, maturity, contractSize);
    }

    /// @inheritdoc IOptionPS
    function getExerciseCost(
        UD60x18 strike,
        UD60x18 contractSize
    ) public view returns (uint256 totalExerciseCost, uint256 fee) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        address exerciseToken = l.getExerciseToken();

        UD60x18 _exerciseCost = l.isCall ? contractSize * strike : contractSize;

        fee = l.toTokenDecimals(_exerciseCost * FEE, exerciseToken);
        totalExerciseCost = l.toTokenDecimals(_exerciseCost, exerciseToken) + fee;
    }

    /// @inheritdoc IOptionPS
    function getExerciseValue(UD60x18 strike, UD60x18 contractSize) public view returns (uint256) {
        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        return l.toTokenDecimals(l.isCall ? contractSize : contractSize * strike, l.getCollateral());
    }

    /// @inheritdoc IOptionPS
    function exercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfOptionExpired(maturity);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        (uint256 totalExerciseCost, uint256 fee) = getExerciseCost(strike, contractSize);

        address exerciseToken = l.getExerciseToken();
        IERC20(exerciseToken).safeTransferFrom(msg.sender, address(this), totalExerciseCost);
        IERC20(exerciseToken).safeTransfer(FEE_RECEIVER, fee);

        l.totalExercised[strike][maturity] = l.totalExercised[strike][maturity] + contractSize;

        uint256 longTokenId = TokenType.Long.formatTokenId(maturity, strike);
        uint256 longExercisedTokenId = TokenType.LongExercised.formatTokenId(maturity, strike);

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        _mintUD60x18(msg.sender, longExercisedTokenId, contractSize);

        emit Exercise(
            msg.sender,
            strike,
            maturity,
            contractSize,
            l.fromTokenDecimals(totalExerciseCost, exerciseToken),
            l.fromTokenDecimals(fee, exerciseToken)
        );
    }

    /// @inheritdoc IOptionPS
    function cancelExercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external nonReentrant {
        _revertIfOptionExpired(maturity);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        uint256 longTokenId = TokenType.Long.formatTokenId(maturity, strike);
        uint256 longExercisedTokenId = TokenType.LongExercised.formatTokenId(maturity, strike);

        l.totalExercised[strike][maturity] = l.totalExercised[strike][maturity] - contractSize;

        _burnUD60x18(msg.sender, longExercisedTokenId, contractSize);
        _mintUD60x18(msg.sender, longTokenId, contractSize);

        address exerciseToken = l.getExerciseToken();

        (uint256 totalExerciseCost, uint256 fee) = getExerciseCost(strike, contractSize);
        IERC20(exerciseToken).safeTransfer(msg.sender, totalExerciseCost - fee);

        emit CancelExercise(
            msg.sender,
            strike,
            maturity,
            contractSize,
            l.fromTokenDecimals(totalExerciseCost - fee, exerciseToken)
        );
    }

    /// @inheritdoc IOptionPS
    function settleLong(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external nonReentrant returns (uint256 exerciseValue) {
        _revertIfOptionNotExpired(maturity);

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();
        uint256 longExercisedTokenId = TokenType.LongExercised.formatTokenId(maturity, strike);

        exerciseValue = getExerciseValue(strike, contractSize);

        address collateral = l.getCollateral();

        _burnUD60x18(msg.sender, longExercisedTokenId, contractSize);
        IERC20(collateral).safeTransfer(msg.sender, exerciseValue);

        emit SettleLong(msg.sender, strike, maturity, contractSize, l.fromTokenDecimals(exerciseValue, collateral));
    }

    /// @inheritdoc IOptionPS
    function settleShort(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external nonReentrant returns (uint256 collateralAmount, uint256 exerciseTokenAmount) {
        _revertIfOptionNotExpired(maturity);

        {
            uint256 shortTokenId = TokenType.Short.formatTokenId(maturity, strike);
            _burnUD60x18(msg.sender, shortTokenId, contractSize);
        }

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        UD60x18 _collateralAmount;
        UD60x18 _exerciseTokenAmount;

        {
            UD60x18 totalUnderwritten = l.totalUnderwritten[strike][maturity];
            UD60x18 percentageExercised = l.totalExercised[strike][maturity] / totalUnderwritten;
            _collateralAmount = (l.isCall ? contractSize : contractSize * strike) * (ONE - percentageExercised);
            _exerciseTokenAmount = (l.isCall ? contractSize * strike : contractSize) * percentageExercised;
        }

        {
            address collateral = l.getCollateral();
            address exerciseToken = l.getExerciseToken();

            collateralAmount = l.toTokenDecimals(_collateralAmount, collateral);
            exerciseTokenAmount = l.toTokenDecimals(_exerciseTokenAmount, exerciseToken);

            IERC20(collateral).safeTransfer(msg.sender, collateralAmount);
            IERC20(exerciseToken).safeTransfer(msg.sender, exerciseTokenAmount);
        }

        emit SettleShort(msg.sender, strike, maturity, contractSize, _collateralAmount, _exerciseTokenAmount);
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

    /// @notice Revert if option has expired
    function _revertIfOptionExpired(uint64 maturity) internal view {
        if (block.timestamp >= maturity) revert OptionPS__OptionExpired(maturity);
    }

    /// @notice Revert if option has not expired
    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert OptionPS__OptionNotExpired(maturity);
    }

    /// @notice `_beforeTokenTransfer` wrapper, updates `tokenIds` set
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
