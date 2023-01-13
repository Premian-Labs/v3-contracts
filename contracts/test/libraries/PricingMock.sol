// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Pricing} from "../../libraries/Pricing.sol";

contract PricingMock {
    // TODO:
    // function fromPool(bool isBuy) external view returns (Pricing.Args memory) {
    //     PoolStorage.Layout storage l = PoolStorage.layout();
    //     return Pricing.fromPool(l, isBuy);
    // }

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
