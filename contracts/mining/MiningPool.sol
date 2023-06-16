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

import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO, ONE} from "../libraries/Constants.sol";

import {IMiningPool} from "./IMiningPool.sol";
import {IPriceRepository} from "./IPriceRepository.sol";
import {MiningPoolStorage} from "./MiningPoolStorage.sol";
import {IPaymentSplitter} from "./IPaymentSplitter.sol";

import "forge-std/console2.sol";

contract MiningPool is ERC1155Base, ERC1155Enumerable, ERC165Base, IMiningPool, ReentrancyGuard {
    using MiningPoolStorage for IERC20;
    using MiningPoolStorage for int128;
    using MiningPoolStorage for MiningPoolStorage.Layout;
    using MiningPoolStorage for UD60x18;
    using SafeCast for uint256;

    // caller must approve token
    function writeFrom(address longReceiver, UD60x18 contractSize) external nonReentrant {
        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();
        if (msg.sender != l.underwriter) revert MiningPool__UnderwriterNotAuthorized(msg.sender);

        IERC20(l.base).safeTransferFromUD60x18(l.underwriter, address(this), l.toTokenDecimals(contractSize, true));

        uint64 maturity = (block.timestamp - (block.timestamp % 24 hours) + 8 hours + l.expiryDuration).toUint64();
        UD60x18 price = IPriceRepository(l.priceRepository).getPrice(l.base, l.quote);
        UD60x18 strike = OptionMath.roundToNearestTenth(price * l.discount);

        uint256 longTokenId = formatTokenId(TokenType.LONG, maturity, strike);
        uint256 shortTokenId = formatTokenId(TokenType.SHORT, maturity, strike);

        _mintUD60x18(longReceiver, longTokenId, contractSize);
        _mintUD60x18(l.underwriter, shortTokenId, contractSize);

        emit WriteFrom(l.underwriter, longReceiver, contractSize, strike, maturity);
    }

    function exercise(uint256 longTokenId, UD60x18 contractSize) external nonReentrant {
        (TokenType tokenType, uint64 maturity, int128 _strike) = parseTokenId(longTokenId);
        if (tokenType != TokenType.LONG) revert MiningPool__TokenTypeNotLong();

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();

        uint256 lockupStart = maturity + l.exerciseDuration;
        uint256 lockupEnd = lockupStart + l.lockupDuration;

        _revertIfOptionNotExpired(maturity);
        _revertIfLockupNotExpired(lockupStart, lockupEnd);

        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
        UD60x18 strike = _strike.fromInt128ToUD60x18();

        if (settlementPrice < strike) revert MiningPool__OptionOutTheMoney(settlementPrice, strike);

        UD60x18 exerciseValue = contractSize;
        UD60x18 exerciseCost = l.toTokenDecimals(strike * contractSize, false);

        if (block.timestamp >= lockupEnd) {
            UD60x18 intrinsicValue = settlementPrice - strike;

            exerciseValue = (intrinsicValue * contractSize) / settlementPrice;
            exerciseValue = exerciseValue * (ONE - l.penalty);

            IERC20(l.base).safeTransferUD60x18(l.underwriter, l.toTokenDecimals(contractSize - exerciseValue, true));
            exerciseCost = ZERO;
        }

        if (exerciseCost > ZERO) {
            IERC20(l.quote).safeTransferFromUD60x18(msg.sender, l.paymentSplitter, exerciseCost);
            // TODO: IPaymentSplitter(l.paymentSplitter).reward(exerciseCost);
        }

        _burnUD60x18(msg.sender, longTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(msg.sender, l.toTokenDecimals(exerciseValue, true));

        emit Exercise(msg.sender, contractSize, exerciseValue, exerciseCost, settlementPrice, strike, maturity);
    }

    function settle(uint256 shortTokenId, UD60x18 contractSize) external nonReentrant {
        (TokenType tokenType, uint64 maturity, int128 _strike) = parseTokenId(shortTokenId);
        if (tokenType != TokenType.SHORT) revert MiningPool__TokenTypeNotShort();

        _revertIfOptionNotExpired(maturity);

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();
        UD60x18 settlementPrice = IPriceRepository(l.priceRepository).getPriceAt(l.base, l.quote, maturity);
        UD60x18 strike = _strike.fromInt128ToUD60x18();

        if (settlementPrice >= strike) revert MiningPool__OptionInTheMoney(settlementPrice, strike);

        _burnUD60x18(l.underwriter, shortTokenId, contractSize);
        IERC20(l.base).safeTransferUD60x18(l.underwriter, l.toTokenDecimals(contractSize, true));

        emit Settle(l.underwriter, contractSize, settlementPrice, strike, maturity);
    }

    // TODO: make internal/ move to storage
    /**
     * @notice Calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity Timestamp of option maturity
     * @param strike Strike price
     * @return tokenId Token id
     */
    function formatTokenId(TokenType tokenType, uint64 maturity, UD60x18 strike) public pure returns (uint256 tokenId) {
        tokenId =
            (uint256(tokenType) << 248) +
            (uint256(maturity) << 128) +
            uint256(int256(strike.fromUD60x18ToInt128()));
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

    function _mintUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _mint(account, tokenId, amount.unwrap(), "");
    }

    function _burnUD60x18(address account, uint256 tokenId, UD60x18 amount) internal {
        _burn(account, tokenId, amount.unwrap());
    }

    function _revertIfOptionNotExpired(uint64 maturity) internal view {
        if (block.timestamp < maturity) revert MiningPool__OptionNotExpired(maturity);
    }

    function _revertIfLockupNotExpired(uint256 lockupStart, uint256 lockupEnd) internal view {
        if (block.timestamp >= lockupStart && block.timestamp < lockupEnd)
            revert MiningPool__LockupNotExpired(lockupStart, lockupEnd);
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
