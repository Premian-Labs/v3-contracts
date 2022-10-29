// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";

import {Math} from "./Math.sol";
import {WadMath} from "./WadMath.sol";

import {PoolStorage} from "../pool/PoolStorage.sol";

/**
 * @notice This class implements the methods necessary for computing price movements within a tick range.
 *         Warnings
 *         --------
 *         This class should not be used for computations that span multiple ticks.
 *         Instead, the user should use the methods of this class to simplify
 *         computations for more complex price calculations.
 */
library Pricing {
    using LinkedList for LinkedList.List;
    using PoolStorage for PoolStorage.Layout;
    using WadMath for uint256;

    error Pricing__InvalidQuantityArgs();
    error Pricing__PriceCannotBeComputedWithinTickRange();
    error Pricing__PriceOutOfRange();
    error Pricing__UpperNotGreaterThanLower();

    struct Args {
        uint256 liquidityRate; // Amount of liquidity
        uint256 marketPrice; // The current market price
        uint256 minTickDistance; // The minimum distance between two ticks
        uint256 lower; // The normalized price of the lower bound of the range
        uint256 upper; // The normalized price of the upper bound of the range
        Position.Side tradeSide; // The direction of the trade
    }

    function fromPool(PoolStorage.Layout storage l, Position.Side tradeSide)
        internal
        view
        returns (Pricing.Args memory)
    {
        uint256 currentTick = l.tick;

        return
            Args(
                l.liquidityRate,
                l.marketPrice,
                l.minTickDistance(),
                currentTick,
                l.tickIndex.getNextNode(currentTick),
                tradeSide
            );
    }

    function proportion(Args memory args) internal pure returns (uint256) {
        if (args.lower >= args.upper)
            revert Pricing__UpperNotGreaterThanLower();
        if (args.lower > args.marketPrice || args.marketPrice > args.upper)
            Pricing__PriceOutOfRange();

        return (args.marketPrice - args.lower).divWad(args.upper - args.lower);
    }

    /**
     *Find the number of ticks of an active tick range. Used to compute
     *the aggregate, bid or ask liquidity either of the pool or the range order.
     *
     * Example:
     *   min_tick_distance = 0.01
     *   lower = 0.01
     *   upper = 0.03
     *   0.01                0.02               0.03
     *      |xxxxxxxxxxxxxxxxxx|xxxxxxxxxxxxxxxxxx|
     *  Then there are two active ticks, 0.01 and 0.02, within the active tick
     *  range.
     *  num_ticks = 2
     */
    function amountOfTicksBetween(Args memory args)
        internal
        pure
        returns (uint256)
    {
        if (args.lower >= args.upper)
            revert Pricing__UpperNotGreaterThanLower();

        // ToDo : Do we need this assertion like in python ?
        //        assert (num_ticks % 1) == 0, \
        //            'The number of ticks within an active tick range has to be an integer.'

        return (args.upper - args.lower).divWad(args.minTickDistance);
    }

    function liquidity(Args memory args) internal pure returns (uint256) {
        return args.liquidityRate.mulWad(amountOfTicksBetween(args));
    }

    function bidLiquidity(Args memory args) internal pure returns (uint256) {
        return proportion(args, args.marketPrice).mulWad(liquidity(args));
    }

    function askLiquidity(Args memory args) internal pure returns (uint256) {
        return
            (1e18 - proportion(args, args.marketPrice)).mulWad(liquidity(args));
    }

    /**
     * @notice Returns the maximum trade size (askLiquidity or bidLiquidity depending on the TradeSide).
     */
    function maxTradeSize(Args memory args) internal pure returns (uint256) {
        return
            args.tradeSide == Position.Side.BUY
                ? askLiquidity(args)
                : bidLiquidity(args);
    }

    /**
     * @notice         Computes price reached from the current lower/upper tick after
     *                 buying/selling `trade_size` amount of contracts.
     */
    function price(Args memory args, uint256 tradeSize)
        internal
        pure
        returns (uint256)
    {
        bool isBuy = args.tradeSide == Position.Side.BUY;

        uint256 liq = liquidity(args);
        if (liq == 0) return isBuy ? args.upper : args.lower;

        uint256 proportion = tradeSize.divWad(liq);

        if (proportion > 1)
            revert Pricing__PriceCannotBeComputedWithinTickRange();

        return
            isBuy
                ? args.lower + (args.upper - args.lower).mulWad(proportion)
                : args.upper - (args.upper - args.lower).mulWad(proportion);
    }

    /**
     * @notice Gets the next market price within a tick range after buying/selling `tradeSize` amount of contracts.
     */
    function nextPrice(uint256 tradeSize) internal pure returns (uint256) {
        uint256 offset = args.tradeSide == Position.Side.BUY
            ? bidLiquidity(args)
            : askLiquidity(args);
        return price(args, offset + tradeSize);
    }
}
