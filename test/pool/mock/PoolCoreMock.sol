// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {Position} from "contracts/libraries/Position.sol";
import {Pricing} from "contracts/libraries/Pricing.sol";
import {UD50x28} from "contracts/libraries/UD50x28.sol";
import {SD49x28} from "contracts/libraries/SD49x28.sol";

import {PoolInternal} from "contracts/pool/PoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

contract PoolCoreMock is IPoolCoreMock, PoolInternal {
    using PoolStorage for IERC20;
    using PoolStorage for PoolStorage.Layout;
    using Position for Position.KeyInternal;

    constructor(
        address factory,
        address router,
        address wrappedNativeToken,
        address feeReceiver,
        address referral,
        address settings,
        address vaultRegistry,
        address vxPremia
    ) PoolInternal(factory, router, wrappedNativeToken, feeReceiver, referral, settings, vaultRegistry, vxPremia) {}

    function _getPricing(bool isBuy) external view returns (Pricing.Args memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _getPricing(l, isBuy);
    }

    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId) {
        return PoolStorage.formatTokenId(operator, lower, upper, orderType);
    }

    function quoteOBHash(QuoteOB memory quoteOB) external view returns (bytes32) {
        return _quoteOBHash(quoteOB);
    }

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (uint8 version, address operator, UD60x18 lower, UD60x18 upper, Position.OrderType orderType)
    {
        return PoolStorage.parseTokenId(tokenId);
    }

    function exerciseFee(
        address taker,
        UD60x18 size,
        UD60x18 intrinsicValue,
        UD60x18 strike,
        bool isCallPool
    ) external view returns (UD60x18) {
        return _exerciseFee(taker, size, intrinsicValue, strike, isCallPool);
    }

    function protocolFees() external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.toPoolTokenDecimals(l.protocolFees);
    }

    function exposed_cross(bool isBuy) external {
        _cross(isBuy);
    }

    function exposed_getStrandedArea() external view returns (UD60x18 lower, UD60x18 upper) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _getStrandedArea(l);
    }

    function exposed_getStrandedMarketPriceUpdate(
        Position.KeyInternal memory p,
        bool isBid
    ) external pure returns (UD50x28) {
        return _getStrandedMarketPriceUpdate(p, isBid);
    }

    function exposed_isMarketPriceStranded(Position.KeyInternal memory p, bool isBid) external view returns (bool) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _isMarketPriceStranded(l, p, isBid);
    }

    function exposed_mint(address account, uint256 id, UD60x18 amount) external {
        _mint(account, id, amount.unwrap(), "");
    }

    function getCurrentTick() external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.currentTick;
    }

    function getLiquidityRate() external view returns (UD50x28) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.liquidityRate;
    }

    function getGlobalFeeRate() external view returns (UD50x28) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.globalFeeRate;
    }

    function exposed_getTick(UD60x18 price) external view returns (IPoolInternal.Tick memory) {
        return _getTick(price);
    }

    function exposed_depositFeeAndTicksUpdate(
        Position.Key memory p,
        UD60x18 belowLower,
        UD60x18 belowUpper,
        UD60x18 size,
        uint256 tokenId
    ) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.KeyInternal memory pI = Position.toKeyInternal(p, l.strike, l.isCallPool);
        Position.Data storage pData = l.positions[Position.keyHash(p)];
        _depositFeeAndTicksUpdate(l, pData, pI, belowLower, belowUpper, size, tokenId);
    }

    function getLongRate() external view returns (UD50x28) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.longRate;
    }

    function exposed_isRateNonTerminating(UD60x18 lower, UD60x18 upper) external pure returns (bool) {
        return _isRateNonTerminating(lower, upper);
    }

    function getShortRate() external view returns (UD50x28) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.shortRate;
    }

    function mint(address account, uint256 id, UD60x18 amount) external {
        _mint(account, id, amount.unwrap(), "");
    }

    function getPositionData(Position.KeyInternal memory p) external view returns (Position.Data memory) {
        return PoolStorage.layout().positions[p.keyHash()];
    }

    function forceUpdateClaimableFees(Position.KeyInternal memory p) external {
        PoolStorage.Layout storage l = PoolStorage.layout();

        _updateClaimableFees(
            l,
            p,
            l.positions[p.keyHash()],
            _balanceOfUD60x18(p.owner, PoolStorage.formatTokenId(p.operator, p.lower, p.upper, p.orderType))
        );
    }

    function forceUpdateLastDeposit(Position.KeyInternal memory p, uint256 timestamp) external {
        PoolStorage.layout().positions[p.keyHash()].lastDeposit = timestamp;
    }

    function safeTransferIgnoreDustUD60x18(address to, UD60x18 value) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        IERC20(l.getPoolToken()).safeTransferIgnoreDust(to, value);
    }

    function safeTransferIgnoreDust(address to, uint256 value) external {
        PoolStorage.Layout storage l = PoolStorage.layout();
        IERC20(l.getPoolToken()).safeTransferIgnoreDust(to, value);
    }

    function getPositionFeeRate(Position.Key memory p) external view returns (SD49x28) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        Position.Data storage pData = l.positions[Position.keyHash(p)];
        return pData.lastFeeRate;
    }

    function exposed_roundDown(UD60x18 value) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.roundDown(value);
    }

    function exposed_roundDownUD60x18(UD60x18 value) external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.roundDownUD60x18(value);
    }

    function exposed_roundDownSD59x18(SD59x18 value) external view returns (SD59x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.roundDownSD59x18(value);
    }

    function exposed_roundUp(UD60x18 value) external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.roundUp(value);
    }

    function exposed_roundUpUD60x18(UD60x18 value) external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.roundUpUD60x18(value);
    }
}
