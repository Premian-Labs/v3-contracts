// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {IPoolTrade} from "./IPoolTrade.sol";

contract PoolTrade is IPoolTrade, PoolInternal {
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
    ) external view returns (UD60x18) {
        return _getTradeQuote(size, isBuy);
    }

    /// @inheritdoc IPoolTrade
    function fillQuote(
        TradeQuote memory tradeQuote,
        UD60x18 size,
        Signature memory signature
    ) external {
        _fillQuote(
            FillQuoteArgsInternal(msg.sender, size, signature),
            tradeQuote
        );
    }

    /// @inheritdoc IPoolTrade
    function trade(
        UD60x18 size,
        bool isBuy,
        UD60x18 premiumLimit
    ) external returns (UD60x18 totalPremium, Delta memory delta) {
        return
            _trade(
                TradeArgsInternal(
                    msg.sender,
                    size,
                    isBuy,
                    premiumLimit,
                    0,
                    true
                )
            );
    }

    /// @inheritdoc IPoolTrade
    function swapAndTrade(
        SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        UD60x18 premiumLimit
    )
        external
        payable
        returns (
            UD60x18 totalPremium,
            Delta memory delta,
            uint256 swapOutAmount
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (swapOutAmount, ) = _swap(s);

        (totalPremium, delta) = _trade(
            TradeArgsInternal(
                msg.sender,
                size,
                isBuy,
                premiumLimit,
                swapOutAmount,
                true
            )
        );

        return (totalPremium, delta, swapOutAmount);
    }

    /// @inheritdoc IPoolTrade
    function tradeAndSwap(
        SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        UD60x18 premiumLimit
    )
        external
        returns (
            UD60x18 totalPremium,
            Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        (totalPremium, delta) = _trade(
            TradeArgsInternal(msg.sender, size, isBuy, premiumLimit, 0, false)
        );

        if (delta.collateral <= iZERO) return (totalPremium, delta, 0, 0);

        s.amountInMax = delta.collateral.intoUD60x18().unwrap();

        if (l.getPoolToken() != s.tokenIn) revert Pool__InvalidSwapTokenIn();
        (tokenOutReceived, collateralReceived) = _swap(s);

        return (totalPremium, delta, collateralReceived, tokenOutReceived);
    }

    /// @inheritdoc IPoolTrade
    function cancelTradeQuotes(bytes32[] calldata hashes) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        for (uint256 i = 0; i < hashes.length; i++) {
            l.tradeQuoteAmountFilled[msg.sender][hashes[i]] = UD60x18.wrap(
                type(uint256).max
            );
            emit CancelTradeQuote(msg.sender, hashes[i]);
        }
    }

    /// @inheritdoc IPoolTrade
    function isTradeQuoteValid(
        TradeQuote memory tradeQuote,
        UD60x18 size,
        Signature memory sig
    ) external view returns (bool, InvalidQuoteError) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        bytes32 tradeQuoteHash = _tradeQuoteHash(tradeQuote);
        return
            _areQuoteAndBalanceValid(
                l,
                FillQuoteArgsInternal(msg.sender, size, sig),
                tradeQuote,
                tradeQuoteHash
            );
    }

    /// @inheritdoc IPoolTrade
    function getTradeQuoteFilledAmount(
        address provider,
        bytes32 tradeQuoteHash
    ) external view returns (UD60x18) {
        return
            PoolStorage.layout().tradeQuoteAmountFilled[provider][
                tradeQuoteHash
            ];
    }
}
