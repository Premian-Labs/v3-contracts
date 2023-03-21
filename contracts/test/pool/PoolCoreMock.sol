// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

import {PoolInternal} from "../../pool/PoolInternal.sol";
import {PoolStorage} from "../../pool/PoolStorage.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

contract PoolCoreMock is IPoolCoreMock, PoolInternal {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address factory,
        address router,
        address permit2,
        address exchangeHelper,
        address wrappedNativeToken,
        address feeReceiver
    )
        PoolInternal(
            factory,
            router,
            permit2,
            exchangeHelper,
            wrappedNativeToken,
            feeReceiver
        )
    {}

    function _getPricing(
        bool isBuy
    ) external view returns (Pricing.Args memory) {
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

    function tradeQuoteHash(
        TradeQuote memory tradeQuote
    ) external view returns (bytes32) {
        return _tradeQuoteHash(tradeQuote);
    }

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (
            uint8 version,
            address operator,
            UD60x18 lower,
            UD60x18 upper,
            Position.OrderType orderType
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }

    function protocolFees() external view returns (uint256) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return l.toPoolTokenDecimals(l.protocolFees);
    }
}
