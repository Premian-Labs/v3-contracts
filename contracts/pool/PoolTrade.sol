// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IPoolTrade} from "./IPoolTrade.sol";

import {IERC3156FlashBorrower} from "../interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "../interfaces/IERC3156FlashLender.sol";
import {iZERO, ZERO} from "../libraries/Constants.sol";
import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";

contract PoolTrade is IPoolTrade, PoolInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    // ToDo : Define final value
    // ToDo : Make this part of global pool settings ?
    UD60x18 constant FLASH_LOAN_FEE = UD60x18.wrap(0.0009e18); // 0.09%

    bytes32 constant FLASH_LOAN_CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(
        address factory,
        address router,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver,
        address vxPremia
    )
        PoolInternal(
            factory,
            router,
            exchangeHelper,
            wrappedNativeToken,
            feeReceiver,
            vxPremia
        )
    {}

    /// @inheritdoc IPoolTrade
    function getQuoteAMM(
        address taker,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premiumNet, uint256 takerFee) {
        return _getQuoteAMM(taker, size, isBuy);
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteRFQ(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata signature,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (uint256 premiumTaker, Position.Delta memory delta)
    {
        return
            _fillQuoteRFQ(
                FillQuoteRFQArgsInternal(
                    msg.sender,
                    size,
                    signature,
                    _wrapNativeToken(),
                    true
                ),
                quoteRFQ,
                permit
            );
    }

    /// @inheritdoc IPoolTrade
    function swapAndFillQuoteRFQ(
        SwapArgs calldata s,
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata signature,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (
            uint256 premiumTaker,
            Position.Delta memory delta,
            uint256 swapOutAmount
        )
    {
        _ensureValidSwapTokenOut(s.tokenOut);
        (swapOutAmount, ) = _swap(s, permit, false, true);

        (premiumTaker, delta) = _fillQuoteRFQ(
            FillQuoteRFQArgsInternal(
                msg.sender,
                size,
                signature,
                swapOutAmount,
                true
            ),
            quoteRFQ,
            Permit2.emptyPermit()
        );
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteRFQAndSwap(
        SwapArgs memory s,
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata signature,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (
            uint256 premiumTaker,
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        (premiumTaker, delta) = _fillQuoteRFQ(
            FillQuoteRFQArgsInternal(
                msg.sender,
                size,
                signature,
                _wrapNativeToken(),
                false
            ),
            quoteRFQ,
            permit
        );

        if (delta.collateral.unwrap() <= 0) return (premiumTaker, delta, 0, 0);

        s.amountInMax = PoolStorage.layout().toPoolTokenDecimals(
            delta.collateral.intoUD60x18()
        );

        _ensureValidSwapTokenIn(s.tokenIn);
        (tokenOutReceived, collateralReceived) = _swap(
            s,
            Permit2.emptyPermit(),
            true,
            false
        );

        if (tokenOutReceived > 0) {
            IERC20(s.tokenOut).safeTransfer(s.refundAddress, tokenOutReceived);
        }
    }

    /// @inheritdoc IPoolTrade
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (uint256 totalPremium, Position.Delta memory delta)
    {
        return
            _trade(
                TradeArgsInternal(
                    msg.sender,
                    size,
                    isBuy,
                    premiumLimit,
                    _wrapNativeToken(),
                    true
                ),
                permit
            );
    }

    /// @inheritdoc IPoolTrade
    function swapAndTrade(
        SwapArgs calldata s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (
            uint256 totalPremium,
            Position.Delta memory delta,
            uint256 swapOutAmount
        )
    {
        _ensureValidSwapTokenOut(s.tokenOut);
        (swapOutAmount, ) = _swap(s, permit, false, true);

        (totalPremium, delta) = _trade(
            TradeArgsInternal(
                msg.sender,
                size,
                isBuy,
                premiumLimit,
                swapOutAmount,
                true
            ),
            Permit2.emptyPermit()
        );
    }

    /// @inheritdoc IPoolTrade
    function tradeAndSwap(
        SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data calldata permit
    )
        external
        payable
        nonReentrant
        returns (
            uint256 totalPremium,
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        (totalPremium, delta) = _trade(
            TradeArgsInternal(
                msg.sender,
                size,
                isBuy,
                premiumLimit,
                _wrapNativeToken(),
                false
            ),
            permit
        );

        if (delta.collateral.unwrap() <= 0) return (totalPremium, delta, 0, 0);

        s.amountInMax = PoolStorage.layout().toPoolTokenDecimals(
            delta.collateral.intoUD60x18()
        );

        _ensureValidSwapTokenIn(s.tokenIn);
        (tokenOutReceived, collateralReceived) = _swap(
            s,
            Permit2.emptyPermit(),
            true,
            false
        );

        if (tokenOutReceived > 0) {
            IERC20(s.tokenOut).safeTransfer(s.refundAddress, tokenOutReceived);
        }
    }

    /// @inheritdoc IPoolTrade
    function cancelQuotesRFQ(bytes32[] calldata hashes) external nonReentrant {
        PoolStorage.Layout storage l = PoolStorage.layout();
        for (uint256 i = 0; i < hashes.length; i++) {
            l.quoteRFQAmountFilled[msg.sender][hashes[i]] = UD60x18.wrap(
                type(uint256).max
            );
            emit CancelQuoteRFQ(msg.sender, hashes[i]);
        }
    }

    /// @inheritdoc IPoolTrade
    function isQuoteRFQValid(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata sig
    ) external view returns (bool, InvalidQuoteRFQError) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        bytes32 quoteRFQHash = _quoteRFQHash(quoteRFQ);
        return
            _areQuoteRFQAndBalanceValid(
                l,
                FillQuoteRFQArgsInternal(msg.sender, size, sig, 0, true),
                quoteRFQ,
                quoteRFQHash
            );
    }

    /// @inheritdoc IPoolTrade
    function getQuoteRFQFilledAmount(
        address provider,
        bytes32 quoteRFQHash
    ) external view returns (UD60x18) {
        return
            PoolStorage.layout().quoteRFQAmountFilled[provider][quoteRFQHash];
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view returns (uint256) {
        _ensurePoolToken(token);
        return IERC20(token).balanceOf(address(this));
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        _ensurePoolToken(token);
        return PoolStorage.layout().toPoolTokenDecimals(_flashFee(amount));
    }

    function _flashFee(uint256 amount) internal view returns (UD60x18) {
        return
            PoolStorage.layout().fromPoolTokenDecimals(amount) * FLASH_LOAN_FEE;
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        _ensurePoolToken(token);
        PoolStorage.Layout storage l = PoolStorage.layout();

        uint256 startBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(address(receiver), amount);

        UD60x18 fee = _flashFee(amount);
        uint256 _fee = l.toPoolTokenDecimals(fee);

        if (
            IERC3156FlashBorrower(receiver).onFlashLoan(
                msg.sender,
                token,
                amount,
                _fee,
                data
            ) != FLASH_LOAN_CALLBACK_SUCCESS
        ) revert Pool__FlashLoanCallbackFailed();

        uint256 endBalance = IERC20(token).balanceOf(address(this));
        uint256 endBalanceRequired = startBalance + _fee;

        if (endBalance < endBalanceRequired) revert Pool__FlashLoanNotRepayed();

        emit FlashLoan(
            msg.sender,
            address(receiver),
            l.fromPoolTokenDecimals(amount),
            fee
        );

        return true;
    }

    function _ensurePoolToken(address token) internal view {
        if (token != PoolStorage.layout().getPoolToken())
            revert Pool__NotPoolToken(token);
    }
}
