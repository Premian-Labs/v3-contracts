// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Pricing} from "../../libraries/Pricing.sol";
import {UD50x28} from "../../libraries/UD50x28.sol";

contract PricingMock {
    function proportion(UD60x18 lower, UD60x18 upper, UD50x28 marketPrice) external pure returns (UD50x28) {
        return Pricing.proportion(lower, upper, marketPrice);
    }

    function amountOfTicksBetween(UD60x18 lower, UD60x18 upper) external pure returns (UD60x18) {
        return Pricing.amountOfTicksBetween(lower, upper);
    }

    function liquidity(Pricing.Args memory args) external pure returns (UD60x18) {
        return Pricing.liquidity(args);
    }

    function bidLiquidity(Pricing.Args memory args) external pure returns (UD60x18) {
        return Pricing.bidLiquidity(args);
    }

    function askLiquidity(Pricing.Args memory args) external pure returns (UD60x18) {
        return Pricing.askLiquidity(args);
    }

    function maxTradeSize(Pricing.Args memory args) external pure returns (UD60x18) {
        return Pricing.maxTradeSize(args);
    }

    function price(Pricing.Args memory args, UD60x18 tradeSize) external pure returns (UD50x28) {
        return Pricing.price(args, tradeSize);
    }

    function nextPrice(Pricing.Args memory args, UD60x18 tradeSize) external pure returns (UD50x28) {
        return Pricing.nextPrice(args, tradeSize);
    }
}
