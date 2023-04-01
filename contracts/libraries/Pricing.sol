// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";
import {Position} from "../libraries/Position.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

import {IPricing} from "./IPricing.sol";

import {ZERO, ONE} from "./Constants.sol";

/// @notice This class implements the methods necessary for computing price movements within a tick range.
///         Warnings
///         --------
///         This class should not be used for computations that span multiple ticks.
///         Instead, the user should use the methods of this class to simplify
///         computations for more complex price calculations.
library Pricing {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for PoolStorage.Layout;

    UD60x18 internal constant MIN_TICK_DISTANCE = UD60x18.wrap(0.001e18); // 0.001
    UD60x18 internal constant MIN_TICK_PRICE = UD60x18.wrap(0.001e18); // 0.001
    UD60x18 internal constant MAX_TICK_PRICE = UD60x18.wrap(1e18); // 1

    struct Args {
        UD60x18 liquidityRate; // Amount of liquidity | 18 decimals
        UD60x18 marketPrice; // The current market price | 18 decimals
        UD60x18 lower; // The normalized price of the lower bound of the range | 18 decimals
        UD60x18 upper; // The normalized price of the upper bound of the range | 18 decimals
        bool isBuy; // The direction of the trade
    }

    function proportion(
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 marketPrice
    ) internal pure returns (UD60x18) {
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower();
        if (lower > marketPrice || marketPrice > upper)
            revert IPricing.Pricing__PriceOutOfRange();

        return (marketPrice - lower) / (upper - lower);
    }

    function proportion(Args memory args) internal pure returns (UD60x18) {
        return proportion(args.lower, args.upper, args.marketPrice);
    }

    /// @notice Find the number of ticks of an active tick range. Used to compute
    /// the aggregate, bid or ask liquidity either of the pool or the range order.
    ///
    /// Example:
    ///   min_tick_distance = 0.01
    ///   lower = 0.01
    ///   upper = 0.03
    ///   0.01                0.02               0.03
    ///      |xxxxxxxxxxxxxxxxxx|xxxxxxxxxxxxxxxxxx|
    ///  Then there are two active ticks, 0.01 and 0.02, within the active tick
    ///  range.
    ///  num_ticks = 2
    function amountOfTicksBetween(
        UD60x18 lower,
        UD60x18 upper
    ) internal pure returns (UD60x18) {
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower();

        return (upper - lower) / MIN_TICK_DISTANCE;
    }

    function amountOfTicksBetween(
        Args memory args
    ) internal pure returns (UD60x18) {
        return amountOfTicksBetween(args.lower, args.upper);
    }

    function liquidity(Args memory args) internal pure returns (UD60x18) {
        return args.liquidityRate * amountOfTicksBetween(args);
    }

    function bidLiquidity(Args memory args) internal pure returns (UD60x18) {
        return proportion(args) * liquidity(args);
    }

    function askLiquidity(Args memory args) internal pure returns (UD60x18) {
        return (ONE - proportion(args)) * liquidity(args);
    }

    /// @notice Returns the maximum trade size (askLiquidity or bidLiquidity depending on the TradeSide).
    function maxTradeSize(Args memory args) internal pure returns (UD60x18) {
        return args.isBuy ? askLiquidity(args) : bidLiquidity(args);
    }

    /// @notice Computes price reached from the current lower/upper tick after
    ///         buying/selling `trade_size` amount of contracts.
    function price(
        Args memory args,
        UD60x18 tradeSize
    ) internal pure returns (UD60x18) {
        UD60x18 liq = liquidity(args);
        if (liq == ZERO) return args.isBuy ? args.upper : args.lower;

        UD60x18 _proportion;
        if (tradeSize > ZERO) _proportion = tradeSize / liq;

        if (_proportion > ONE)
            revert IPricing.Pricing__PriceCannotBeComputedWithinTickRange();

        return
            args.isBuy
                ? args.lower + (args.upper - args.lower) * _proportion
                : args.upper - (args.upper - args.lower) * _proportion;
    }

    /// @notice Gets the next market price within a tick range after buying/selling `tradeSize` amount of contracts.
    function nextPrice(
        Args memory args,
        UD60x18 tradeSize
    ) internal pure returns (UD60x18) {
        UD60x18 offset = args.isBuy ? bidLiquidity(args) : askLiquidity(args);
        return price(args, offset + tradeSize);
    }
}
