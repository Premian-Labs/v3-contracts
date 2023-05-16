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

    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId);

    function quoteRFQHash(
        IPoolInternal.QuoteRFQ memory quoteRFQ
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

    function exposed_cross(bool isBuy) external;

    function exposed_getStrandedArea()
        external
        view
        returns (UD60x18 lower, UD60x18 upper);

    function exposed_getStrandedMarketPriceUpdate(
        Position.KeyInternal memory p,
        bool isBid
    ) external pure returns (UD60x18);

    function exposed_isMarketPriceStranded(
        Position.KeyInternal memory p,
        bool isBid
    ) external view returns (bool);

    function getCurrentTick() external view returns (UD60x18);

    function getLiquidityRate() external view returns (UD60x18);
}
