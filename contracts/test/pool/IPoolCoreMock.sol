// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Position} from "../../libraries/Position.sol";
import {Pricing} from "../../libraries/Pricing.sol";

interface IPoolCoreMock {
    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId);

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
        );
}
