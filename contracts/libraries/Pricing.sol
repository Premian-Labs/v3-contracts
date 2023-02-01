// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

import {Position} from "../libraries/Position.sol";
import {PRBMathExtended} from "../libraries/PRBMathExtended.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

import {IPricing} from "./IPricing.sol";

/// @notice This class implements the methods necessary for computing price movements within a tick range.
///         Warnings
///         --------
///         This class should not be used for computations that span multiple ticks.
///         Instead, the user should use the methods of this class to simplify
///         computations for more complex price calculations.
library Pricing {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using PoolStorage for PoolStorage.Layout;
    using PRBMathExtended for UD60x18;

    UD60x18 private constant ONE = UD60x18.wrap(1e18);

    uint256 internal constant MIN_TICK_DISTANCE = 1e15; // 0.001
    uint256 internal constant MIN_TICK_PRICE = 1e15; // 0.001
    uint256 internal constant MAX_TICK_PRICE = 1e18; // 1

    struct Args {
        uint256 liquidityRate; // Amount of liquidity
        uint256 marketPrice; // The current market price
        uint256 lower; // The normalized price of the lower bound of the range
        uint256 upper; // The normalized price of the upper bound of the range
        bool isBuy; // The direction of the trade
    }

    function proportion(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice
    ) internal pure returns (UD60x18) {
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower();
        if (lower > marketPrice || marketPrice > upper)
            revert IPricing.Pricing__PriceOutOfRange();

        return ud(marketPrice - lower).div(ud(upper - lower));
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
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        if (lower >= upper) revert IPricing.Pricing__UpperNotGreaterThanLower();

        return (upper - lower) / MIN_TICK_DISTANCE;
    }

    function amountOfTicksBetween(
        Args memory args
    ) internal pure returns (uint256) {
        return amountOfTicksBetween(args.lower, args.upper);
    }

    function liquidity(Args memory args) internal pure returns (UD60x18) {
        return ud(args.liquidityRate * amountOfTicksBetween(args));
    }

    function bidLiquidity(Args memory args) internal pure returns (UD60x18) {
        return proportion(args).mul(liquidity(args));
    }

    function askLiquidity(Args memory args) internal pure returns (UD60x18) {
        return (ONE.sub(proportion(args))).mul(liquidity(args));
    }

    /// @notice Returns the maximum trade size (askLiquidity or bidLiquidity depending on the TradeSide).
    function maxTradeSize(Args memory args) internal pure returns (UD60x18) {
        return args.isBuy ? askLiquidity(args) : bidLiquidity(args);
    }

    /// @notice Computes price reached from the current lower/upper tick after
    ///         buying/selling `trade_size` amount of contracts.
    function price(
        Args memory args,
        uint256 tradeSize
    ) internal pure returns (UD60x18) {
        UD60x18 liq = liquidity(args);
        if (liq.uw() == 0) return ud(args.isBuy ? args.upper : args.lower);

        UD60x18 _proportion;
        if (tradeSize > 0) _proportion = ud(tradeSize).div(liq);

        if (_proportion.gt(ONE))
            revert IPricing.Pricing__PriceCannotBeComputedWithinTickRange();

        return
            ud(
                args.isBuy
                    ? args.lower +
                        ud(args.upper - args.lower).mul(_proportion).uw()
                    : args.upper -
                        ud(args.upper - args.lower).mul(_proportion).uw()
            );
    }

    /// @notice Gets the next market price within a tick range after buying/selling `tradeSize` amount of contracts.
    function nextPrice(
        Args memory args,
        uint256 tradeSize
    ) internal pure returns (uint256) {
        uint256 offset = args.isBuy
            ? bidLiquidity(args).uw()
            : askLiquidity(args).uw();
        return price(args, offset + tradeSize).uw();
    }
}
