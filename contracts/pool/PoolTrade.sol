// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC3156FlashBorrower} from "@solidstate/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@solidstate/contracts/interfaces/IERC3156FlashLender.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {Position} from "../libraries/Position.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IPoolTrade} from "./IPoolTrade.sol";

contract PoolTrade is IPoolTrade, PoolInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    UD60x18 internal constant FLASH_LOAN_FEE = UD60x18.wrap(0.0009e18); // 0.09%

    bytes32 internal constant FLASH_LOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver,
        address referral,
        address settings,
        address vaultRegistry,
        address vxPremia
    ) PoolInternal(factory, router, wrappedNativeToken, feeReceiver, referral, settings, vaultRegistry, vxPremia) {}

    /// @inheritdoc IPoolTrade
    function getQuoteAMM(
        address taker,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premiumNet, uint256 takerFee) {
        return _getQuoteAMM(taker, size, isBuy);
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteOB(
        QuoteOB calldata quoteOB,
        UD60x18 size,
        Signature calldata signature,
        address referrer
    ) external nonReentrant returns (uint256 premiumTaker, Position.Delta memory delta) {
        return _fillQuoteOB(FillQuoteOBArgsInternal(msg.sender, referrer, size, signature), quoteOB);
    }

    /// @inheritdoc IPoolTrade
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        address referrer
    ) external nonReentrant returns (uint256 totalPremium, Position.Delta memory delta) {
        return _trade(TradeArgsInternal(msg.sender, referrer, size, isBuy, premiumLimit));
    }

    /// @inheritdoc IPoolTrade
    function cancelQuotesOB(bytes32[] calldata hashes) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();
        for (uint256 i = 0; i < hashes.length; i++) {
            l.quoteOBAmountFilled[msg.sender][hashes[i]] = ud(type(uint256).max);
            emit CancelQuoteOB(msg.sender, hashes[i]);
        }
    }

    /// @inheritdoc IPoolTrade
    function isQuoteOBValid(
        address user,
        QuoteOB calldata quoteOB,
        UD60x18 size,
        Signature calldata sig
    ) external view returns (bool, InvalidQuoteOBError) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _revertIfOptionExpired(l);
        bytes32 quoteOBHash = _quoteOBHash(quoteOB);
        return
            _areQuoteOBAndBalanceValid(l, FillQuoteOBArgsInternal(user, address(0), size, sig), quoteOB, quoteOBHash);
    }

    /// @inheritdoc IPoolTrade
    function getQuoteOBFilledAmount(address provider, bytes32 quoteOBHash) external view returns (UD60x18) {
        return PoolStorage.layout().quoteOBAmountFilled[provider][quoteOBHash];
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view returns (uint256) {
        _revertIfNotPoolToken(token);
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        _revertIfNotPoolToken(token);
        return PoolStorage.layout().toPoolTokenDecimals(_flashFee(amount));
    }

    /// @notice Returns the fee required for a flash loan of `amount`
    function _flashFee(uint256 amount) internal view returns (UD60x18) {
        return PoolStorage.layout().fromPoolTokenDecimals(amount) * FLASH_LOAN_FEE;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        _revertIfNotPoolToken(token);
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 startBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(address(receiver), amount);

        UD60x18 fee = _flashFee(amount);
        l.protocolFees = l.protocolFees + fee;
        uint256 _fee = l.toPoolTokenDecimals(fee);

        if (
            IERC3156FlashBorrower(receiver).onFlashLoan(msg.sender, token, amount, _fee, data) !=
            FLASH_LOAN_CALLBACK_SUCCESS
        ) revert Pool__FlashLoanCallbackFailed();

        uint256 endBalance = IERC20(token).balanceOf(address(this));
        uint256 endBalanceRequired = startBalance + _fee;

        if (endBalance < endBalanceRequired) revert Pool__FlashLoanNotRepayed();

        emit FlashLoan(msg.sender, address(receiver), l.fromPoolTokenDecimals(amount), fee);

        return true;
    }

    /// @notice Revert if `token` is not the pool token
    function _revertIfNotPoolToken(address token) internal view {
        if (token != PoolStorage.layout().getPoolToken()) revert Pool__NotPoolToken(token);
    }
}
