// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

import {IPoolInternal} from "../../pool/IPoolInternal.sol";

interface IPoolCoreMock {
    function _getPricing(
        bool isBuy
    ) external view returns (Pricing.Args memory);

    function _getStrandedArea()
        external
        view
        returns (UD60x18 lower, UD60x18 upper);

    function _currentTick() external view returns (UD60x18);

    function _crossTick(bool isBuy) external;

    function _isMarketPriceStrandedMock(
        Position.KeyInternal memory p,
        bool isBid
    ) external view returns (bool);

    function _getStrandedMarketPriceUpdateMock(
        Position.KeyInternal memory p,
        bool isBid
    ) external pure returns (UD60x18);

    function _liquidityRate() external view returns (UD60x18);

    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId);

    function tradeQuoteHash(
        IPoolInternal.TradeQuote memory tradeQuote
    ) external view returns (bytes32);

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
        );

    function protocolFees() external view returns (uint256);
}
