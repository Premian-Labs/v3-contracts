// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";
import {UD50x28} from "../../libraries/UD50x28.sol";

import {IPoolInternal} from "../../pool/IPoolInternal.sol";

interface IPoolCoreMock {
    function _getPricing(bool isBuy) external view returns (Pricing.Args memory);

    function formatTokenId(
        address operator,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId);

    function quoteOBHash(IPoolInternal.QuoteOB memory quoteOB) external view returns (bytes32);

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (uint8 version, address operator, UD60x18 lower, UD60x18 upper, Position.OrderType orderType);

    function exerciseFee(
        address taker,
        UD60x18 size,
        UD60x18 intrinsicValue,
        UD60x18 strike,
        bool isCallPool
    ) external view returns (UD60x18);

    function protocolFees() external view returns (uint256);

    function exposed_cross(bool isBuy) external;

    function exposed_getStrandedArea() external view returns (UD60x18 lower, UD60x18 upper);

    function exposed_getStrandedMarketPriceUpdate(
        Position.KeyInternal memory p,
        bool isBid
    ) external pure returns (UD50x28);

    function exposed_isMarketPriceStranded(Position.KeyInternal memory p, bool isBid) external view returns (bool);

    function exposed_mint(address account, uint256 id, UD60x18 amount) external;

    function getCurrentTick() external view returns (UD60x18);

    function getLiquidityRate() external view returns (UD50x28);

    function getLongRate() external view returns (UD50x28);

    function getShortRate() external view returns (UD50x28);

    function exposed_getTick(UD60x18 price) external view returns (IPoolInternal.Tick memory);

    function exposed_isRateNonTerminating(UD60x18 lower, UD60x18 upper) external pure returns (bool);

    function mint(address account, uint256 id, UD60x18 amount) external;

    function safeTransferIgnoreDust(address to, uint256 value) external;

    function safeTransferIgnoreDustUD60x18(address to, UD60x18 value) external;
}
