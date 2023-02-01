// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";
import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address exchangeHelper,
        address wrappedNativeToken
    ) PoolInternal(exchangeHelper, wrappedNativeToken) {}

    /// @inheritdoc IPoolCore
    function takerFee(
        uint256 size,
        uint256 premium
    ) external pure returns (uint256) {
        return _takerFee(size, premium);
    }

    /// @inheritdoc IPoolCore
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address underlying,
            address baseOracle,
            address underlyingOracle,
            uint256 strike,
            uint64 maturity,
            bool isCallPool
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (
            l.base,
            l.underlying,
            l.baseOracle,
            l.underlyingOracle,
            l.strike,
            l.maturity,
            l.isCallPool
        );
    }

    /// @inheritdoc IPoolCore
    function getQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256) {
        return _getQuote(size, isBuy);
    }

    /// @inheritdoc IPoolCore
    function claim(Position.Key memory p) external {
        _claim(p);
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 size,
        uint256 maxSlippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _deposit(p, belowLower, belowUpper, size, maxSlippage, 0);
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
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _deposit(
            p,
            belowLower,
            belowUpper,
            size,
            maxSlippage,
            0,
            isBidIfStrandedMarketPrice
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
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (uint256 creditAmount, ) = _swap(s);

        _deposit(p, belowLower, belowUpper, size, maxSlippage, creditAmount);
    }

    /// @inheritdoc IPoolCore
    function withdraw(
        Position.Key memory p,
        uint256 size,
        uint256 maxSlippage
    ) external {
        if (p.operator != msg.sender) revert Pool__NotAuthorized();
        _withdraw(p, size, maxSlippage);
    }

    /// @inheritdoc IPoolCore
    function fillQuote(
        TradeQuote memory quote,
        uint256 size,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _fillQuote(msg.sender, quote, size, v, r, s);
    }

    /// @inheritdoc IPoolCore
    function trade(
        uint256 size,
        bool isBuy
    ) external returns (uint256 totalPremium, Delta memory delta) {
        return _trade(msg.sender, size, isBuy, 0, true);
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
            msg.sender,
            size,
            isBuy,
            swapOutAmount,
            true
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
        (totalPremium, delta) = _trade(msg.sender, size, isBuy, 0, false);

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
    function getQuoteNonce(address user) external view returns (uint256) {
        return PoolStorage.layout().quoteNonce[user];
    }
}
