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
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {ONE} from "../libraries/Constants.sol";

import {IMiningPool} from "./IMiningPool.sol";
import {IPriceRepository} from "./IPriceRepository.sol";
import {MiningPoolStorage} from "./MiningPoolStorage.sol";
import {IPaymentSplitter} from "./IPaymentSplitter.sol";

import "forge-std/console2.sol";

contract MiningPool is ERC1155Base, ERC1155Enumerable, ERC165Base, IMiningPool, ReentrancyGuard {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // caller must approve token
    function writeFrom(address underwriter, address longReceiver, UD60x18 contractSize) external nonReentrant {
        if (
            msg.sender != underwriter && ERC1155BaseStorage.layout().operatorApprovals[underwriter][msg.sender] == false
        ) revert MiningPool__OperatorNotAuthorized(msg.sender);

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();
        _safeTransferFromUD60x18(l.base, underwriter, address(this), _toTokenDecimals(l, contractSize, true));

        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = (timestamp8AMUTC + l.expiryDuration).toUint64();

        // NOTE: Spot price must be 18 decimals
        UD60x18 spot = IPriceRepository(l.priceRepository).getDailyOpenPriceFrom(l.base, l.quote, timestamp8AMUTC);
        UD60x18 _strike = OptionMath.roundToNearestTenth(spot * l.discount);
        int128 strike = _fromUD60x18ToInt128(_strike);

        uint256 longTokenId = formatTokenId(TokenType.LONG, maturity, strike);
        uint256 shortTokenId = formatTokenId(TokenType.SHORT, maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(underwriter, shortTokenId, contractSize);

        // TODO: add strike/ maturity to event?
        emit WriteFrom(underwriter, longReceiver, contractSize);
    }

    function exercise(uint256 longTokenId, UD60x18 contractSize) external nonReentrant {
        (TokenType tokenType, uint64 maturity, int128 _strike) = parseTokenId(longTokenId);

        if (tokenType != TokenType.LONG) revert MiningPool__TokenTypeNotLong(tokenType);
        _revertIfOptionNotExpired(maturity);

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();
        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getDailyOpenPriceFrom(l.base, l.quote, maturity);
        UD60x18 strike = ud(int256(_strike).toUint256());

        if (settlementPrice < strike) revert MiningPool__OptionOutTheMoney(settlementPrice, strike);

        uint256 lockupPeriodStart = maturity + l.exerciseDuration;
        uint256 lockupPeriodEnd = lockupPeriodStart + l.lockupDuration;

        UD60x18 exerciseValue = contractSize;

        if (block.timestamp >= lockupPeriodStart) {
            if (block.timestamp >= lockupPeriodEnd) {
                UD60x18 intrinsicValue = settlementPrice - strike;
                exerciseValue = (intrinsicValue * contractSize) / settlementPrice;
                exerciseValue = exerciseValue * (ONE - l.penalty);
            } else {
                revert MiningPool__LockupPeriodNotExpired(block.timestamp, lockupPeriodStart, lockupPeriodEnd);
            }
        }

        UD60x18 exerciseCost = _toTokenDecimals(l, strike * contractSize, false);
        _safeTransferFromUD60x18(l.quote, msg.sender, l.paymentSplitter, exerciseCost);
        // TODO: IPaymentSplitter(l.paymentSplitter).reward(exerciseCost);

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        _safeTransferUD60x18(l.base, msg.sender, _toTokenDecimals(l, exerciseValue, true));

        // TODO: add strike/ maturity to event?
        emit Exercise(msg.sender, contractSize, exerciseValue, settlementPrice);
    }

    function settle() external nonReentrant {}

    /**
     * @notice Calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity Timestamp of option maturity
     * @param strike Strike price
     * @return tokenId Token id
     */
    function formatTokenId(TokenType tokenType, uint64 maturity, int128 strike) public pure returns (uint256 tokenId) {
        tokenId = (uint256(tokenType) << 248) + (uint256(maturity) << 128) + uint256(int256(strike));
    }

    /**
     * @notice Derive option maturity and strike price from ERC1155 token id
     * @param tokenId Token id
     * @return tokenType TokenType enum
     * @return maturity Timestamp of option maturity
     * @return strike Option strike price
     */
    function parseTokenId(uint256 tokenId) public pure returns (TokenType tokenType, uint64 maturity, int128 strike) {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike := tokenId
        }
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

    function _mintUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _mint(account, tokenId, amount.unwrap(), "");
    }

    function _burnUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _burn(account, tokenId, amount.unwrap());
    }

    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert MiningPool__OptionNotExpired(maturity);
    }

    // TODO: move to storage
    /// @notice Adjust decimals of a value with 18 decimals to match the token decimals
    function _toTokenDecimals(
        MiningPoolStorage.Layout storage l,
        UD60x18 value,
        bool isBase
    ) internal view returns (UD60x18) {
        uint8 decimals = isBase ? l.baseDecimals : l.quoteDecimals;
        return ud(OptionMath.scaleDecimals(value.unwrap(), 18, decimals));
    }

    /// @notice Adjust decimals of a value with token decimals to 18 decimals
    function _fromTokenDecimals(
        MiningPoolStorage.Layout storage l,
        UD60x18 value,
        bool isBase
    ) internal view returns (UD60x18) {
        uint8 decimals = isBase ? l.baseDecimals : l.quoteDecimals;
        return ud(OptionMath.scaleDecimals(value.unwrap(), decimals, 18));
    }

    function _fromUD60x18ToInt128(UD60x18 u) internal pure returns (int128) {
        return u.unwrap().toInt256().toInt128();
    }

    function _fromInt128ToUD60x18(int128 i) internal pure returns (UD60x18) {
        return ud(int256(i).toUint256());
    }

    function _safeTransferFromUD60x18(address token, address from, address to, UD60x18 amount) internal {
        IERC20(token).safeTransferFrom(from, to, amount.unwrap());
    }

    function _safeTransferUD60x18(address token, address to, UD60x18 amount) internal {
        IERC20(token).safeTransfer(to, amount.unwrap());
    }
}
