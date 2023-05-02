// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO} from "../libraries/Constants.sol";

import {IPoolCore} from "./IPoolCore.sol";
import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolCore is IPoolCore, PoolInternal, ReentrancyGuard {
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.Key;
    using SafeERC20 for IERC20;

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver,
        address settings,
        address vxPremia
    )
        PoolInternal(
            factory,
            router,
            wrappedNativeToken,
            feeReceiver,
            settings,
            vxPremia
        )
    {}

    /// @inheritdoc IPoolCore
    function marketPrice() external view returns (UD60x18) {
        return PoolStorage.layout().marketPrice;
    }

    /// @inheritdoc IPoolCore
    function takerFee(
        address taker,
        UD60x18 size,
        uint256 premium,
        bool isPremiumNormalized
    ) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        return
            l.toPoolTokenDecimals(
                _takerFee(
                    l,
                    taker,
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
    function claim(
        Position.Key calldata p
    ) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _claim(p.toKeyInternal(l.strike, l.isCallPool));
    }

    /// @inheritdoc IPoolCore
    function getClaimableFees(
        Position.Key calldata p
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
    function writeFrom(
        address underwriter,
        address longReceiver,
        UD60x18 size
    ) external nonReentrant {
        return _writeFrom(underwriter, longReceiver, size);
    }

    /// @inheritdoc IPoolCore
    function annihilate(UD60x18 size) external nonReentrant {
        _annihilate(msg.sender, size);
    }

    /// @inheritdoc IPoolCore
    function exercise() external nonReentrant returns (uint256) {
        return _exercise(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function exerciseFor(
        address[] calldata holders,
        uint256 cost
    ) external nonReentrant returns (uint256 totalExerciseValue) {
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
    function settle() external nonReentrant returns (uint256) {
        return _settle(msg.sender, ZERO);
    }

    /// @inheritdoc IPoolCore
    function settleFor(
        address[] calldata holders,
        uint256 cost
    ) external nonReentrant returns (uint256 totalCollateral) {
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
    ) external nonReentrant returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        _ensureOperator(p.operator);
        return _settlePosition(p.toKeyInternal(l.strike, l.isCallPool), ZERO);
    }

    /// @inheritdoc IPoolCore
    function settlePositionFor(
        Position.Key[] calldata p,
        uint256 cost
    ) external nonReentrant returns (uint256 totalCollateral) {
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
    function transferPosition(
        Position.Key calldata srcP,
        address newOwner,
        address newOperator,
        UD60x18 size
    ) external nonReentrant {
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
