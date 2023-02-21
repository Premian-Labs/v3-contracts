// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";
import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;

    constructor(
        address factory,
        address exchangeHelper,
        address wrappedNativeToken
    ) PoolInternal(factory, exchangeHelper, wrappedNativeToken) {}

    /// @inheritdoc IPoolCore
    function takerFee(
        uint256 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256) {
        return
            _takerFee(PoolStorage.layout(), size, premium, isPremiumNormalized);
    }

    /// @inheritdoc IPoolCore
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address baseOracle,
            address quoteOracle,
            uint256 strike,
            uint64 maturity,
            bool isCallPool
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (
            l.base,
            l.quote,
            l.baseOracle,
            l.quoteOracle,
            l.strike,
            l.maturity,
            l.isCallPool
        );
    }

    /// @inheritdoc IPoolCore
    function getTradeQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256) {
        return _getTradeQuote(size, isBuy);
    }

    /// @inheritdoc IPoolCore
    function claim(Position.Key memory p) external {
        _claim(p);
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(
        Position.Key memory p
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];

        (uint256 pendingClaimableFees, ) = _pendingClaimableFees(l, p, pData);

        return pData.claimableFees + pendingClaimableFees;
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage
    ) external {
        _ensureOperator(p.operator);
        _deposit(p, belowLower, belowUpper, size, maxSlippage, 0, address(0));
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage,
        bool isBidIfStrandedMarketPrice
    ) external {
        _ensureOperator(p.operator);
        _deposit(
            p,
            DepositArgsInternal(
                belowLower,
                belowUpper,
                size,
                maxSlippage,
                0,
                address(0),
                isBidIfStrandedMarketPrice
            )
        );
    }

    /// @inheritdoc IPoolCore
    function swapAndDeposit(
        SwapArgs memory s,
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage
    ) external payable {
        _ensureOperator(p.operator);
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (uint256 creditAmount, ) = _swap(s);

        _deposit(
            p,
            belowLower,
            belowUpper,
            size,
            maxSlippage,
            creditAmount,
            s.refundAddress
        );
    }

    /// @inheritdoc IPoolCore
    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 maxSlippage
    ) external {
        _ensureOperator(p.operator);
        _withdraw(p, size, maxSlippage);
    }

    /// @inheritdoc IPoolCore
    function fillQuote(
        TradeQuote memory tradeQuote,
        uint256 size,
        Signature memory signature
    ) external {
        _fillQuote(
            FillQuoteArgsInternal(msg.sender, size, signature),
            tradeQuote
        );
    }

    /// @inheritdoc IPoolCore
    function trade(
        uint256 size,
        bool isBuy
    ) external returns (uint256 totalPremium, Delta memory delta) {
        return _trade(TradeArgsInternal(msg.sender, size, isBuy, 0, true));
    }

    /// @inheritdoc IPoolCore
    function swapAndTrade(
        SwapArgs memory s,
        uint256 size,
        bool isBuy
    )
        external
        payable
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 swapOutAmount
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (swapOutAmount, ) = _swap(s);

        (totalPremium, delta) = _trade(
            TradeArgsInternal(msg.sender, size, isBuy, swapOutAmount, true)
        );

        return (totalPremium, delta, swapOutAmount);
    }

    /// @inheritdoc IPoolCore
    function tradeAndSwap(
        SwapArgs memory s,
        uint256 size,
        bool isBuy
    )
        external
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        (totalPremium, delta) = _trade(
            TradeArgsInternal(msg.sender, size, isBuy, 0, false)
        );

        if (delta.collateral <= 0) return (totalPremium, delta, 0, 0);

        s.amountInMax = uint256(delta.collateral);

        if (l.getPoolToken() != s.tokenIn) revert Pool__InvalidSwapTokenIn();
        (tokenOutReceived, collateralReceived) = _swap(s);

        return (totalPremium, delta, collateralReceived, tokenOutReceived);
    }

    /// @inheritdoc IPoolCore
    function annihilate(uint256 size) external {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise(address holder) external returns (uint256) {
        return _exercise(holder);
    }

    /// @inheritdoc IPoolCore
    function settle(address holder) external returns (uint256) {
        return _settle(holder);
    }

    /// @inheritdoc IPoolCore
    function settlePosition(Position.Key memory p) external returns (uint256) {
        return _settlePosition(p);
    }

    /// @inheritdoc IPoolCore
    function getNearestTicksBelow(
        uint256 lower,
        uint256 upper
    )
        external
        view
        returns (uint256 nearestBelowLower, uint256 nearestBelowUpper)
    {
        return _getNearestTicksBelow(lower, upper);
    }

    /// @inheritdoc IPoolCore
    function cancelTradeQuotes(bytes32[] calldata hashes) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        for (uint256 i = 0; i < hashes.length; i++) {
            l.tradeQuoteAmountFilled[msg.sender][hashes[i]] = type(uint256).max;
            emit CancelTradeQuote(msg.sender, hashes[i]);
        }
    }

    /// @inheritdoc IPoolCore
    function isTradeQuoteValid(
        TradeQuote memory tradeQuote,
        uint256 size,
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

    /// @inheritdoc IPoolCore
    function getTradeQuoteFilledAmount(
        address provider,
        bytes32 tradeQuoteHash
    ) external view returns (uint256) {
        return
            PoolStorage.layout().tradeQuoteAmountFilled[provider][
                tradeQuoteHash
            ];
    }
}
