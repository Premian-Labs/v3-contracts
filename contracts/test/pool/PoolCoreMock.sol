// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

import {PoolInternal} from "../../pool/PoolInternal.sol";
import {PoolStorage} from "../../pool/PoolStorage.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

contract PoolCoreMock is IPoolCoreMock, PoolInternal {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address factory,
        address exchangeHelper,
        address wrappedNativeToken
    ) PoolInternal(factory, exchangeHelper, wrappedNativeToken) {}

    function _getPricing(
        bool isBuy
    ) external view returns (Pricing.Args memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();
        return _getPricing(l, isBuy);
    }

    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
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
            uint256 lower,
            uint256 upper,
            Position.OrderType orderType
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }

    function marketPrice() external view returns (uint256) {
        return PoolStorage.layout().marketPrice;
    }

    function protocolFees() external view returns (uint256) {
        return PoolStorage.layout().protocolFees;
    }
}
