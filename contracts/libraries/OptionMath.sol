// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    /// @notice Returns true if the maturity day is Friday
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is Friday, false otherwise
    function isFriday(uint64 maturity) internal pure returns (bool) {
        return DateTime.getDayOfWeek(maturity) == DateTime.DOW_FRI;
    }

    /// @notice Returns true if the maturity day is the last Friday of the month
    /// @param maturity The maturity timestamp of the option
    /// @return True if the maturity day is the last Friday of the month, false otherwise
    function isLastFriday(uint64 maturity) internal pure returns (bool) {
        uint256 dayOfMonth = DateTime.getDay(maturity);
        uint256 lastDayOfMonth = DateTime.getDaysInMonth(maturity);

        if (lastDayOfMonth - dayOfMonth > 7) return false;
        return isFriday(maturity);
    }

    /// @notice Calculates the time to maturity in seconds
    /// @param maturity The maturity timestamp of the option
    /// @return Time to maturity in seconds
    function calculateTimeToMaturity(
        uint64 maturity
    ) internal view returns (uint256) {
        return maturity - block.timestamp;
    }

    /// @notice Calculates the strike interval for the given spot price
    /// @param spot The spot price of the underlying asset
    /// @return The strike interval
    function calculateStrikeInterval(
        int256 spot
    ) internal pure returns (int256) {
        SD59x18 NEG_ONE_59X18 = wrap(-1e18);
        SD59x18 ONE_59X18 = wrap(1e18);

        SD59x18 FIVE_59X18 = wrap(5e18);
        SD59x18 TEN_59X18 = wrap(10e18);

        SD59x18 SPOT_59X18 = wrap(spot);

        SD59x18 o = SPOT_59X18.log10().floor();

        SD59x18 x = SPOT_59X18.mul(
            TEN_59X18.pow(o.mul(NEG_ONE_59X18).sub(ONE_59X18))
        );

        SD59x18 f = TEN_59X18.pow(o.sub(ONE_59X18));
        SD59x18 y = x.lt(wrap(0.5e18)) ? ONE_59X18.mul(f) : FIVE_59X18.mul(f);
        return unwrap(SPOT_59X18.lt(wrap(1000e18)) ? y : y.ceil());
    }
}
