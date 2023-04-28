// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO} from "../libraries/Constants.sol";

import {IPoolCore} from "./IPoolCore.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolCore is IPoolCore, PoolInternal {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using SafeERC20 for IERC20;

    constructor(
        address factory,
        address router,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver,
        address settings
    )
        PoolInternal(
            factory,
            router,
            exchangeHelper,
            wrappedNativeToken,
            feeReceiver,
            settings
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
            l.toPoolTokenDecimals(
                _takerFee(
                    l,
                    size,
                    l.fromPoolTokenDecimals(premium),
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
    function claim(Position.Key memory p) external returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _claim(p.toKeyInternal(l.strike, l.isCallPool));
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(
        Position.Key memory p
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[p.keyHash()];

        (UD60x18 pendingClaimableFees, ) = _pendingClaimableFees(
            l,
            p.toKeyInternal(l.strike, l.isCallPool),
            pData
        );

        return
            l.toPoolTokenDecimals(pData.claimableFees + pendingClaimableFees);
    }

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit
    ) external payable returns (Position.Delta memory delta) {
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

    /// @inheritdoc IPoolCore
    function deposit(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit,
        bool isBidIfStrandedMarketPrice
    ) external payable returns (Position.Delta memory delta) {
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

    /// @inheritdoc IPoolCore
    function swapAndDeposit(
        SwapArgs memory s,
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice,
        Permit2.Data memory permit
    ) external payable returns (Position.Delta memory delta) {
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

    /// @inheritdoc IPoolCore
    function withdraw(
        Position.Key memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    ) external returns (Position.Delta memory delta) {
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

    /// @inheritdoc IPoolCore
    function withdrawAndSwap(
        SwapArgs memory s,
        Position.Key memory p,
        UD60x18 size,
        UD60x18 minMarketPrice,
        UD60x18 maxMarketPrice
    )
        external
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

    /// @inheritdoc IPoolCore
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size,
        Permit2.Data memory permit
    ) external {
        return _writeFrom(underwriter, longReceiver, size, permit);
    }

    /// @inheritdoc IPoolCore
    function annihilate(UD60x18 size) external {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise() external returns (uint256) {
        return _exercise(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function exerciseFor(
        address[] calldata holders,
        uint256 cost
    ) external returns (uint256 totalExerciseValue) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(cost);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _ensureAuthorizedAgent(holders[i], msg.sender);
                _ensureAuthorizedCost(holders[i], _cost);
            }

            uint256 exerciseValue = _exercise(holders[i], _cost);
            totalExerciseValue = totalExerciseValue + exerciseValue;
        }

        IERC20(l.getPoolToken()).safeTransfer(
            msg.sender,
            holders.length * cost
        );
    }

    /// @inheritdoc IPoolCore
    function settle() external returns (uint256) {
        return _settle(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function settleFor(
        address[] calldata holders,
        uint256 cost
    ) external returns (uint256 totalCollateral) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(cost);

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] != msg.sender) {
                _ensureAuthorizedAgent(holders[i], msg.sender);
                _ensureAuthorizedCost(holders[i], _cost);
            }

            uint256 collateral = _settle(holders[i], _cost);
            totalCollateral = totalCollateral + collateral;
        }

        IERC20(l.getPoolToken()).safeTransfer(
            msg.sender,
            holders.length * cost
        );
    }

    /// @inheritdoc IPoolCore
    function settlePosition(
        Position.Key calldata p
    ) external returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureOperator(p.operator);
        return _settlePosition(p.toKeyInternal(l.strike, l.isCallPool), ZERO);
    }

    /// @inheritdoc IPoolCore
    function settlePositionFor(
        Position.Key[] calldata p,
        uint256 cost
    ) external returns (uint256 totalCollateral) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        UD60x18 _cost = l.fromPoolTokenDecimals(cost);

        for (uint256 i = 0; i < p.length; i++) {
            if (p[i].operator != msg.sender) {
                _ensureAuthorizedAgent(p[i].operator, msg.sender);
                _ensureAuthorizedCost(p[i].operator, _cost);
            }

            uint256 collateral = _settlePosition(
                p[i].toKeyInternal(l.strike, l.isCallPool),
                _cost
            );

            totalCollateral = totalCollateral + collateral;
        }

        IERC20(l.getPoolToken()).safeTransfer(msg.sender, p.length * cost);
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
        PoolStorage.Layout storage l = PoolStorage.layout();

        _ensureOperator(srcP.operator);
        _transferPosition(
            srcP.toKeyInternal(l.strike, l.isCallPool),
            newOwner,
            newOperator,
            size
        );
    }
}
