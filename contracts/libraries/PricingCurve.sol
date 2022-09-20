// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Math} from "./Math.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

/**
 * @notice This class implements the methods necessary for computing price movements within a tick range.
 *         Warnings
 *         --------
 *         This class should not be used for computations that span multiple ticks.
 *         Instead, the user should use the methods of this class to simplify
 *         computations for more complex price calculations.
 */
library PricingCurve {
    error PricingCurve__InvalidQuantityArgs();

    function liqForRange(
        uint256 liq,
        uint256 minTickDistance,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        return liq / (((upper - lower) * minTickDistance) / 1e18);
    }

    function u(
        uint256 liq,
        uint256 minTickDistance,
        uint256 x,
        uint256 lower,
        uint256 upper,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        liq = liqForRange(liq, minTickDistance, lower, upper);
        bool isBuy = tradeSide == PoolStorage.Side.BUY;

        if (liq == 0) return isBuy ? lower : upper;

        uint256 proportion = (x * 1e18) / liq;

        return
            isBuy
                ? lower + ((upper - lower) * proportion) / 1e18
                : upper - ((upper - lower) * proportion) / 1e18;
    }

    function uInv(
        uint256 liq,
        uint256 minTickDistance,
        uint256 p,
        uint256 lower,
        uint256 upper,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        uint256 proportion = tradeSide == PoolStorage.Side.BUY
            ? (p - lower) / (upper - lower)
            : (upper - p) / (upper - lower);

        return
            (liqForRange(liq, minTickDistance, lower, upper) * proportion) /
            1e18;
    }

    function uMean(uint256 start, uint256 end) internal pure returns (uint256) {
        return
            Math.min(start, end) +
            (Math.max(start, end) - Math.min(start, end)) /
            2;
    }

    /**
     * @notice Computes quantity needed to reach `price` from the current
     *         lower/upper tick coming from the buy/sell direction.
     *         |=======q=======|
     *         |--------------------------------------|
     *         L               ^                      U
     *                       Price
     * @param liq Amount of liquidity
     * @param minTickDistance The minimum distance between two ticks
     * @param current The normalized price of the current tick
     * @param currentRight The normalized price of the tick at the right of the current tick
     * @param targetPrice The target price
     * @param tradeSide The direction of the trade
     * @return The quantity needed to reach `price` from the lower/upper tick coming from the buy/sell direction
     */
    function quantity(
        uint256 liq,
        uint256 minTickDistance,
        uint256 current,
        uint256 currentRight,
        uint256 targetPrice,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        if (
            current > targetPrice ||
            targetPrice > currentRight ||
            current == currentRight
        ) revert PricingCurve__InvalidQuantityArgs();

        return
            uInv(
                liq,
                minTickDistance,
                targetPrice,
                current,
                currentRight,
                tradeSide
            );
    }

    /**
     * @notice Calculates the max trade size within the current tick range using the quantity function.
     * @param current The normalized price of the current tick
     * @param currentRight The normalized price of the tick at the right of the current tick
     * @param marketPrice The current normalized market price
     * @param tradeSide The direction of the trade
     * @return The maximum trade size within the current tick range
     */
    function maxTradeSide(
        uint256 liq,
        uint256 minTickDistance,
        uint256 current,
        uint256 currentRight,
        uint256 marketPrice,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        uint256 targetPrice = tradeSide == PoolStorage.Side.BUY
            ? currentRight
            : current;

        return
            Math.abs(
                int256(
                    quantity(
                        liq,
                        minTickDistance,
                        current,
                        currentRight,
                        targetPrice,
                        tradeSide
                    )
                ) -
                    int256(
                        quantity(
                            liq,
                            minTickDistance,
                            current,
                            currentRight,
                            marketPrice,
                            tradeSide
                        )
                    )
            );
    }

    /**
     * @notice Computes price reached from the current lower/upper tick after
     *         buying/selling `trade_size` amount of contracts.
     * @param liq Amount of liquidity
     * @param minTickDistance The minimum distance between two ticks
     * @param current The normalized price of the current tick
     * @param currentRight The normalized price of the tick at the right of the current tick
     * @param size The size of the trade (number of contracts).
     * @param tradeSide The direction of the trade
     * @return The price reached from the current lower/upper tick after buying/selling `trade_size` amount of contracts.
     */
    function price(
        uint256 liq,
        uint256 minTickDistance,
        uint256 current,
        uint256 currentRight,
        uint256 size,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        return u(liq, minTickDistance, size, current, currentRight, tradeSide);
    }

    /**
     * @notice Gets the next market price within a tick range
     * @param liq Amount of liquidity
     * @param minTickDistance The minimum distance between two ticks
     * @param current The normalized price of the current tick
     * @param currentRight The normalized price of the tick at the right of the current tick
     * @param marketPrice The normalized market price
     * @param size The size of the trade
     * @param tradeSide The direction of the trade
     */
    function nextPrice(
        uint256 liq,
        uint256 minTickDistance,
        uint256 current,
        uint256 currentRight,
        uint256 marketPrice,
        uint256 size,
        PoolStorage.Side tradeSide
    ) internal pure returns (uint256) {
        return
            price(
                liq,
                minTickDistance,
                currentRight,
                currentRight,
                size +
                    quantity(
                        liq,
                        minTickDistance,
                        current,
                        currentRight,
                        marketPrice,
                        tradeSide
                    ),
                tradeSide
            );
    }
}
