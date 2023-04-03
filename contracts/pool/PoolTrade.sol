// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IPoolTrade} from "./IPoolTrade.sol";

import {iZERO, ZERO} from "../libraries/Constants.sol";
import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";

contract PoolTrade is IPoolTrade, PoolInternal {
    using SafeERC20 for IERC20;
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address factory,
        address router,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver
    )
        PoolInternal(
            factory,
            router,
            exchangeHelper,
            wrappedNativeToken,
            feeReceiver
        )
    {}

    /// @inheritdoc IPoolTrade
    function getTradeQuote(
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premiumNet, uint256 takerFee) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        (UD60x18 _premiumNet, UD60x18 _takerFee) = _getTradeQuote(size, isBuy);

        return (
            l.toPoolTokenDecimals(_premiumNet),
            l.toPoolTokenDecimals(_takerFee)
        );
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteRFQ(
        QuoteRFQ memory quoteRFQ,
        UD60x18 size,
        Signature memory signature,
        Permit2.Data memory permit
    ) external returns (uint256 premiumTaker, Position.Delta memory delta) {
        UD60x18 premium;
        (premium, delta) = _fillQuoteRFQ(
            FillQuoteRFQArgsInternal(msg.sender, size, signature, 0, true),
            quoteRFQ,
            permit
        );

        return (PoolStorage.layout().toPoolTokenDecimals(premium), delta);
    }

    /// @inheritdoc IPoolTrade
    function swapAndFillQuoteRFQ(
        SwapArgs memory s,
        QuoteRFQ memory quoteRFQ,
        UD60x18 size,
        Signature memory signature,
        Permit2.Data memory permit
    )
        external
        returns (
            uint256 premiumTaker,
            Position.Delta memory delta,
            uint256 swapOutAmount
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (swapOutAmount, ) = _swap(s, permit, false);

        UD60x18 premium;
        (premium, delta) = _fillQuoteRFQ(
            FillQuoteRFQArgsInternal(
                msg.sender,
                size,
                signature,
                swapOutAmount,
                true
            ),
            quoteRFQ,
            permit
        );

        return (l.toPoolTokenDecimals(premium), delta, swapOutAmount);
    }

    /// @inheritdoc IPoolTrade
    function fillQuoteRFQAndSwap(
        SwapArgs memory s,
        QuoteRFQ memory quoteRFQ,
        UD60x18 size,
        Signature memory signature,
        Permit2.Data memory permit
    )
        external
        returns (
            uint256 premiumTaker,
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 premium;
        (premium, delta) = _fillQuoteRFQ(
            FillQuoteRFQArgsInternal(msg.sender, size, signature, 0, false),
            quoteRFQ,
            permit
        );

        uint256 premiumScaled = l.toPoolTokenDecimals(premium);

        if (delta.collateral.unwrap() <= 0) return (premiumScaled, delta, 0, 0);

        s.amountInMax = premiumScaled;

        address poolToken = l.getPoolToken();
        if (poolToken != s.tokenIn) revert Pool__InvalidSwapTokenIn();
        (tokenOutReceived, collateralReceived) = _swap(
            s,
            Permit2.emptyPermit(),
            true
        );

        if (tokenOutReceived > 0) {
            IERC20(s.tokenOut).safeTransfer(s.refundAddress, tokenOutReceived);
        }

        return (premiumScaled, delta, collateralReceived, tokenOutReceived);
    }

    /// @inheritdoc IPoolTrade
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    ) external returns (uint256 totalPremium, Position.Delta memory delta) {
        UD60x18 _totalPremium;
        (_totalPremium, delta) = _trade(
            TradeArgsInternal(msg.sender, size, isBuy, premiumLimit, 0, true),
            permit
        );

        return (PoolStorage.layout().toPoolTokenDecimals(_totalPremium), delta);
    }

    /// @inheritdoc IPoolTrade
    function swapAndTrade(
        SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    )
        external
        payable
        returns (
            uint256 totalPremium,
            Position.Delta memory delta,
            uint256 swapOutAmount
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (swapOutAmount, ) = _swap(s, permit, false);

        UD60x18 _totalPremium;
        (_totalPremium, delta) = _trade(
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

        return (l.toPoolTokenDecimals(_totalPremium), delta, swapOutAmount);
    }

    /// @inheritdoc IPoolTrade
    function tradeAndSwap(
        SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    )
        external
        returns (
            uint256 totalPremium,
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        UD60x18 _totalPremium;
        (_totalPremium, delta) = _trade(
            TradeArgsInternal(msg.sender, size, isBuy, premiumLimit, 0, false),
            permit
        );

        uint256 totalPremiumScaled = l.toPoolTokenDecimals(_totalPremium);

        if (delta.collateral.unwrap() <= 0)
            return (totalPremiumScaled, delta, 0, 0);

        s.amountInMax = totalPremiumScaled;

        address poolToken = l.getPoolToken();
        if (poolToken != s.tokenIn) revert Pool__InvalidSwapTokenIn();
        (tokenOutReceived, collateralReceived) = _swap(
            s,
            Permit2.emptyPermit(),
            true
        );

        if (tokenOutReceived > 0) {
            IERC20(s.tokenOut).safeTransfer(s.refundAddress, tokenOutReceived);
        }

        return (
            totalPremiumScaled,
            delta,
            collateralReceived,
            tokenOutReceived
        );
    }

    /// @inheritdoc IPoolTrade
    function cancelQuotesRFQ(bytes32[] calldata hashes) external {
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
        QuoteRFQ memory quoteRFQ,
        UD60x18 size,
        Signature memory sig
    ) external view returns (bool, InvalidQuoteRFQError) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        bytes32 quoteRFQHash = _quoteRFQHash(quoteRFQ);
        return
            _areQuoteAndBalanceValid(
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
}
