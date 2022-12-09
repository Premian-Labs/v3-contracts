// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";

import {WadMath} from "./WadMath.sol";

import {PoolStorage} from "../pool/PoolStorage.sol";

/// @notice This class implements the methods necessary for computing price movements within a tick range.
///         Warnings
///         --------
///         This class should not be used for computations that span multiple ticks.
///         Instead, the user should use the methods of this class to simplify
///         computations for more complex price calculations.
library Pricing {
    using LinkedList for LinkedList.List;
    using PoolStorage for PoolStorage.Layout;
    using WadMath for uint256;

    error Pricing__InvalidQuantityArgs();
    error Pricing__PriceCannotBeComputedWithinTickRange();
    error Pricing__PriceOutOfRange();
    error Pricing__UpperNotGreaterThanLower();

    uint256 internal constant MIN_TICK_DISTANCE = 1e15; // 0.001
    uint256 internal constant MIN_TICK_PRICE = 1e15; // 0.001
    uint256 internal constant MAX_TICK_PRICE = 1e18; // 1

    struct Args {
        uint256 liquidityRate; // Amount of liquidity
        uint256 marketPrice; // The current market price
        uint256 lower; // The normalized price of the lower bound of the range
        uint256 upper; // The normalized price of the upper bound of the range
        Position.Side tradeSide; // The direction of the trade
    }

    function fromPool(
        PoolStorage.Layout storage l,
        Position.Side tradeSide
    ) internal view returns (Pricing.Args memory) {
        uint256 currentTick = l.currentTick;

        return
            Args(
                l.liquidityRate,
                l.marketPrice,
                currentTick,
                l.tickIndex.getNextNode(currentTick),
                tradeSide
            );
    }

    function proportion(
        uint256 lower,
        uint256 upper,
        uint256 marketPrice
    ) internal pure returns (uint256) {
        if (lower >= upper) revert Pricing__UpperNotGreaterThanLower();
        if (lower > marketPrice || marketPrice > upper)
            revert Pricing__PriceOutOfRange();

        return (marketPrice - lower).divWad(upper - lower);
    }

    function proportion(Args memory args) internal pure returns (uint256) {
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
        if (lower >= upper) revert Pricing__UpperNotGreaterThanLower();

        // ToDo : Do we need this assertion like in python ?
        //        assert (num_ticks % 1) == 0, \
        //            'The number of ticks within an active tick range has to be an integer.'

        return (upper - lower).divWad(MIN_TICK_DISTANCE);
    }

    function amountOfTicksBetween(
        Args memory args
    ) internal pure returns (uint256) {
        return amountOfTicksBetween(args.lower, args.upper);
    }

    function liquidity(Args memory args) internal pure returns (uint256) {
        return args.liquidityRate * amountOfTicksBetween(args);
    }

    function bidLiquidity(Args memory args) internal pure returns (uint256) {
        return proportion(args).mulWad(liquidity(args));
    }

    function askLiquidity(Args memory args) internal pure returns (uint256) {
        return (1e18 - proportion(args)).mulWad(liquidity(args));
    }

    /// @notice Returns the maximum trade size (askLiquidity or bidLiquidity depending on the TradeSide).
    function maxTradeSize(Args memory args) internal pure returns (uint256) {
        return
            args.tradeSide == Position.Side.BUY
                ? askLiquidity(args)
                : bidLiquidity(args);
    }

    /// @notice         Computes price reached from the current lower/upper tick after
    ///                 buying/selling `trade_size` amount of contracts.
    function price(
        Args memory args,
        uint256 tradeSize
    ) internal pure returns (uint256) {
        bool isBuy = args.tradeSide == Position.Side.BUY;

        uint256 liq = liquidity(args);
        if (liq == 0) return isBuy ? args.upper : args.lower;

        uint256 _proportion = tradeSize.divWad(liq);

        if (_proportion > 1)
            revert Pricing__PriceCannotBeComputedWithinTickRange();

        return
            isBuy
                ? args.lower + (args.upper - args.lower).mulWad(_proportion)
                : args.upper - (args.upper - args.lower).mulWad(_proportion);
    }

    /// @notice Gets the next market price within a tick range after buying/selling `tradeSize` amount of contracts.
    function nextPrice(
        Args memory args,
        uint256 tradeSize
    ) internal pure returns (uint256) {
        uint256 offset = args.tradeSide == Position.Side.BUY
            ? bidLiquidity(args)
            : askLiquidity(args);
        return price(args, offset + tradeSize);
    }
}
