// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";

import {IPoolDepositWithdraw} from "./IPoolDepositWithdraw.sol";

contract PoolDepositWithdraw is
    IPoolDepositWithdraw,
    PoolInternal,
    ReentrancyGuard
{
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using SafeERC20 for IERC20;

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

    /// @inheritdoc IPoolDepositWithdraw
    function deposit(
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data calldata permit
    ) external payable nonReentrant returns (Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(p.operator);
        return
            _deposit(
                p.toKeyInternal(l.strike, l.isCallPool),
                DepositArgsInternal(
                    belowLower,
                    belowUpper,
                    size,
                    minMarketPrice,
                    maxMarketPrice,
                    _wrapNativeToken(),
                    msg.sender
                ),
                permit
            );
    }

    /// @inheritdoc IPoolDepositWithdraw
    function deposit(
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data calldata permit,
        bool isBidIfStrandedMarketPrice
    ) external payable nonReentrant returns (Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(p.operator);
        return
            _deposit(
                p.toKeyInternal(l.strike, l.isCallPool),
                DepositArgsInternal(
                    belowLower,
                    belowUpper,
                    size,
                    minMarketPrice,
                    maxMarketPrice,
                    _wrapNativeToken(),
                    msg.sender
                ),
                permit,
                isBidIfStrandedMarketPrice
            );
    }

    /// @inheritdoc IPoolDepositWithdraw
    function swapAndDeposit(
        SwapArgs calldata s,
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data calldata permit
    ) external payable nonReentrant returns (Position.Delta memory delta) {
        _ensureOperator(p.operator);
        _ensureValidSwapTokenOut(s.tokenOut);

        (uint256 creditAmount, ) = _swap(s, permit, false, true);

        PoolStorage.Layout storage l = PoolStorage.layout();

        return
            _deposit(
                p.toKeyInternal(l.strike, l.isCallPool),
                DepositArgsInternal(
                    belowLower,
                    belowUpper,
                    size,
                    minMarketPrice,
                    maxMarketPrice,
                    creditAmount,
                    s.refundAddress
                ),
                Permit2.emptyPermit()
            );
    }

    /// @inheritdoc IPoolDepositWithdraw
    function withdraw(
        Position.Key calldata p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external nonReentrant returns (Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(p.operator);
        return
            _withdraw(
                p.toKeyInternal(l.strike, l.isCallPool),
                size,
                minMarketPrice,
                maxMarketPrice,
                true
            );
    }

    /// @inheritdoc IPoolDepositWithdraw
    function withdrawAndSwap(
        SwapArgs memory s,
        Position.Key calldata p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    )
        external
        nonReentrant
        returns (
            Position.Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        )
    {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(p.operator);
        delta = _withdraw(
            p.toKeyInternal(l.strike, l.isCallPool),
            size,
            minMarketPrice,
            maxMarketPrice,
            false
        );

        if (delta.collateral.unwrap() <= 0) return (delta, 0, 0);

        s.amountInMax = l.toPoolTokenDecimals(delta.collateral.intoUD60x18());

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

        return (delta, collateralReceived, tokenOutReceived);
    }
}
