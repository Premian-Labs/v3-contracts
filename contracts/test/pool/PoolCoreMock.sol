// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

import {PoolInternal} from "../../pool/PoolInternal.sol";
import {PoolStorage} from "../../pool/PoolStorage.sol";
import {IPoolInternal} from "../../pool/IPoolInternal.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

contract PoolCoreMock is IPoolCoreMock, PoolInternal {
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
    ) external pure returns (UD60x18) {
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

    function getLiquidityRate() external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.liquidityRate;
    }

    function exposed_getTick(UD60x18 price) external view returns (IPoolInternal.Tick memory) {
        return _getTick(price);
    }

    function exposed_isRateNonTerminating(UD60x18 lower, UD60x18 upper) external pure returns (bool) {
        return _isRateNonTerminating(lower, upper);
    }

    function getLongRate() external view returns (UD60x18) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.longRate;
    }

    function getShortRate() external view returns (UD60x18) {
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
}
