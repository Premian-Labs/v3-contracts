// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";

import {PoolCore} from "../pool/PoolCore.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

contract PoolCoreMock is IPoolCoreMock, PoolCore {
    using PoolStorage for PoolStorage.Layout;

    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId) {
        return PoolStorage.formatTokenId(operator, lower, upper, orderType);
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

    // TODO : Move to PricingMock
    function proportion(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice
    ) external pure returns (uint256) {
        return Pricing.proportion(lower, upper, marketPrice);
    }

    function amountOfTicksBetween(
        uint256 lower,
        uint256 upper
    ) external pure returns (uint256) {
        return Pricing.amountOfTicksBetween(lower, upper);
    }

    function liquidity(
        Pricing.Args memory args
    ) external pure returns (uint256) {
        return Pricing.liquidity(args);
    }

    function bidLiquidity(
        Pricing.Args memory args
    ) external pure returns (uint256) {
        return Pricing.bidLiquidity(args);
    }

    function askLiquidity(
        Pricing.Args memory args
    ) external pure returns (uint256) {
        return Pricing.askLiquidity(args);
    }

    function maxTradeSize(
        Pricing.Args memory args
    ) external pure returns (uint256) {
        return Pricing.maxTradeSize(args);
    }

    function price(
        Pricing.Args memory args,
        uint256 tradeSize
    ) external pure returns (uint256) {
        return Pricing.price(args, tradeSize);
    }

    function nextPrice(
        Pricing.Args memory args,
        uint256 tradeSize
    ) external pure returns (uint256) {
        return Pricing.nextPrice(args, tradeSize);
    }
}
