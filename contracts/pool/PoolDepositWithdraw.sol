// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

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
        address wrappedNativeToken,
        address feeReceiver,
        address referral,
        address settings,
        address vaultRegistry,
        address vxPremia
    )
        PoolInternal(
            factory,
            router,
            wrappedNativeToken,
            feeReceiver,
            referral,
            settings,
            vaultRegistry,
            vxPremia
        )
    {}

    /// @inheritdoc IPoolDepositWithdraw
    function deposit(
        Position.Key calldata p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external nonReentrant returns (Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _revertIfOperatorNotAuthorized(p.operator);

        return
            _deposit(
                p.toKeyInternal(l.strike, l.isCallPool),
                DepositArgsInternal(
                    belowLower,
                    belowUpper,
                    size,
                    minMarketPrice,
                    maxMarketPrice
                )
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
        bool isBidIfStrandedMarketPrice
    ) external nonReentrant returns (Position.Delta memory delta) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _revertIfOperatorNotAuthorized(p.operator);

        return
            _deposit(
                p.toKeyInternal(l.strike, l.isCallPool),
                DepositArgsInternal(
                    belowLower,
                    belowUpper,
                    size,
                    minMarketPrice,
                    maxMarketPrice
                ),
                isBidIfStrandedMarketPrice
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

        _revertIfOperatorNotAuthorized(p.operator);

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
}
