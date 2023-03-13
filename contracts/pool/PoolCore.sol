// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

import {IPoolCore} from "./IPoolCore.sol";

contract PoolCore is IPoolCore, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;

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

    /// @inheritdoc IPoolCore
    function marketPrice() external view returns (UD60x18) {
        return PoolStorage.layout().marketPrice;
    }

    /// @inheritdoc IPoolCore
    function takerFee(
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        return
            PoolStorage.layout().toPoolTokenDecimals(
                _takerFee(
                    PoolStorage.layout(),
                    size,
                    UD60x18.wrap(l.fromPoolTokenDecimals(premium)),
                    isPremiumNormalized
                )
            );
    }

    /// @inheritdoc IPoolCore
    function getPoolSettings()
        external
        view
        returns (
            address base,
            address quote,
            address oracleAdapter,
            UD60x18 strike,
            uint64 maturity,
            bool isCallPool
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return (
            l.base,
            l.quote,
            l.oracleAdapter,
            l.strike,
            l.maturity,
            l.isCallPool
        );
    }

    /// @inheritdoc IPoolCore
    function claim(Position.Key memory p) external returns (UD60x18) {
        return _claim(p);
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(
        Position.Key memory p
    ) external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];

        (UD60x18 pendingClaimableFees, ) = _pendingClaimableFees(l, p, pData);

        return pData.claimableFees + pendingClaimableFees;
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external {
        _ensureOperator(p.operator);
        _deposit(
            p,
            DepositArgsInternal(
                belowLower,
                belowUpper,
                size,
                minMarketPrice,
                maxMarketPrice,
                0,
                address(0)
            )
        );
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        bool isBidIfStrandedMarketPrice
    ) external {
        _ensureOperator(p.operator);
        _deposit(
            p,
            DepositArgsInternal(
                belowLower,
                belowUpper,
                size,
                minMarketPrice,
                maxMarketPrice,
                0,
                address(0)
            ),
            isBidIfStrandedMarketPrice
        );
    }

    /// @inheritdoc IPoolCore
    function swapAndDeposit(
        SwapArgs memory s,
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external payable {
        _ensureOperator(p.operator);
        PoolStorage.Layout storage l = PoolStorage.layout();

        if (l.getPoolToken() != s.tokenOut) revert Pool__InvalidSwapTokenOut();
        (uint256 creditAmount, ) = _swap(s);

        _deposit(
            p,
            DepositArgsInternal(
                belowLower,
                belowUpper,
                size,
                minMarketPrice,
                maxMarketPrice,
                creditAmount,
                s.refundAddress
            )
        );
    }

    /// @inheritdoc IPoolCore
    function withdraw(
        Position.Key memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external {
        _ensureOperator(p.operator);
        _withdraw(p, size, minMarketPrice, maxMarketPrice);
    }

    /// @inheritdoc IPoolCore
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size
    ) external {
        return _writeFrom(underwriter, longReceiver, size);
    }

    /// @inheritdoc IPoolCore
    function annihilate(UD60x18 size) external {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise(address holder) external returns (UD60x18) {
        return _exercise(holder);
    }

    /// @inheritdoc IPoolCore
    function settle(address holder) external returns (UD60x18) {
        return _settle(holder);
    }

    /// @inheritdoc IPoolCore
    function settlePosition(Position.Key memory p) external returns (UD60x18) {
        return _settlePosition(p);
    }

    /// @inheritdoc IPoolCore
    function getNearestTicksBelow(
        UD60x18 lower,
        UD60x18 upper
    )
        external
        view
        returns (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper)
    {
        return _getNearestTicksBelow(lower, upper);
    }

    function transferPosition(
        Position.Key memory srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external {
        _ensureOperator(srcP.operator);
        _transferPosition(srcP, newOwner, newOperator, size);
    }
}
