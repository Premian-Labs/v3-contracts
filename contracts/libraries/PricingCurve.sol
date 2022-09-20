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
        bool isBuy = side.isBuy();

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
        uint256 proportion = tradeSide.isBuy()
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
}
