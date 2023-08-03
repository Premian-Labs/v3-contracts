// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";
import {UD50x28} from "../libraries/UD50x28.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";
import {PRBMathExtra} from "./PRBMathExtra.sol";

import {IPricing} from "./IPricing.sol";

import {ZERO, UD50_ONE} from "./Constants.sol";

/// @notice This library implements the functions necessary for computing price movements within a tick range.
/// @dev WARNING: This library should not be used for computations that span multiple ticks. Instead, the user should
///      use the functions of this library to simplify computations for more complex price calculations.
library Pricing {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for PoolStorage.Layout;
    using PRBMathExtra for UD60x18;
    using PRBMathExtra for UD50x28;

    struct Args {
        UD50x28 liquidityRate; // Amount of liquidity (28 decimals)
        UD50x28 marketPrice; // The current market price (28 decimals)
        UD60x18 lower; // The normalized price of the lower bound of the range (18 decimals)
        UD60x18 upper; // The normalized price of the upper bound of the range (18 decimals)
        bool isBuy; // The direction of the trade
    }

    /// @notice Returns the percentage by which the market price has passed through the lower and upper prices
    ///         from left to right. Reverts if the market price is not within the range of the lower and upper prices.
    function proportion(UD60x18 lower, UD60x18 upper, UD50x28 marketPrice) internal pure returns (UD50x28) {
        UD60x18 marketPriceUD60 = marketPrice.intoUD60x18();
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower(lower, upper);
        if (lower > marketPriceUD60 || marketPriceUD60 > upper)
            revert IPricing.Pricing__PriceOutOfRange(lower, upper, marketPriceUD60);

        return (marketPrice - lower.intoUD50x28()) / (upper - lower).intoUD50x28();
    }

    /// @notice Returns the percentage by which the market price has passed through the lower and upper prices
    ///         from left to right. Reverts if the market price is not within the range of the lower and upper prices.
    function proportion(Args memory args) internal pure returns (UD50x28) {
        return proportion(args.lower, args.upper, args.marketPrice);
    }

    /// @notice Find the number of ticks of an active tick range. Used to compute the aggregate, bid or ask liquidity
    ///         either of the pool or the range order.
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///         min_tick_distance = 0.01
    ///         lower = 0.01
    ///         upper = 0.03
    ///         num_ticks = 2
    ///
    ///         0.01               0.02               0.03
    ///          |xxxxxxxxxxxxxxxxxx|xxxxxxxxxxxxxxxxxx|
    ///
    ///         Then there are two active ticks, 0.01 and 0.02, within the active tick range.
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    function amountOfTicksBetween(UD60x18 lower, UD60x18 upper) internal pure returns (UD60x18) {
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower(lower, upper);

        return (upper - lower) / PoolStorage.MIN_TICK_DISTANCE;
    }

    /// @notice Returns the number of ticks between `args.lower` and `args.upper`
    function amountOfTicksBetween(Args memory args) internal pure returns (UD60x18) {
        return amountOfTicksBetween(args.lower, args.upper);
    }

    /// @notice Returns the liquidity between `args.lower` and `args.upper`
    function liquidity(Args memory args) internal pure returns (UD60x18) {
        return (args.liquidityRate * amountOfTicksBetween(args).intoUD50x28()).intoUD60x18();
    }

    /// @notice Returns the bid-side liquidity between `args.lower` and `args.upper`
    function bidLiquidity(Args memory args) internal pure returns (UD60x18) {
        return (proportion(args) * liquidity(args).intoUD50x28()).roundToNearestUD60x18();
    }

    /// @notice Returns the ask-side liquidity between `args.lower` and `args.upper`
    function askLiquidity(Args memory args) internal pure returns (UD60x18) {
        return ((UD50_ONE - proportion(args)) * liquidity(args).intoUD50x28()).roundToNearestUD60x18();
    }

    /// @notice Returns the maximum trade size (askLiquidity or bidLiquidity depending on the TradeSide).
    function maxTradeSize(Args memory args) internal pure returns (UD60x18) {
        return args.isBuy ? askLiquidity(args) : bidLiquidity(args);
    }

    /// @notice Computes price reached from the current lower/upper tick after buying/selling `trade_size` amount of
    ///         contracts
    function price(Args memory args, UD60x18 tradeSize) internal pure returns (UD50x28) {
        UD60x18 liq = liquidity(args);
        if (liq == ZERO) return (args.isBuy ? args.upper : args.lower).intoUD50x28();

        UD50x28 _proportion;
        if (tradeSize > ZERO) _proportion = tradeSize.intoUD50x28() / liq.intoUD50x28();

        if (_proportion > UD50_ONE) revert IPricing.Pricing__PriceCannotBeComputedWithinTickRange();

        return
            args.isBuy
                ? args.lower.intoUD50x28() + (args.upper - args.lower).intoUD50x28() * _proportion
                : args.upper.intoUD50x28() - (args.upper - args.lower).intoUD50x28() * _proportion;
    }

    /// @notice Gets the next market price within a tick range after buying/selling `tradeSize` amount of contracts
    function nextPrice(Args memory args, UD60x18 tradeSize) internal pure returns (UD50x28) {
        UD60x18 offset = args.isBuy ? bidLiquidity(args) : askLiquidity(args);
        return price(args, offset + tradeSize);
    }
}
