// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18, ceil, floor, log10, mul, pow, unwrap, wrap} from "@prb/math/src/SD59x18.sol";

import {IPoolInternal} from "../pool/IPoolInternal.sol";

import {DateTime} from "./DateTime.sol";

library OptionMath {
    function isFriday(uint64 maturity) internal pure returns (bool) {
        return DateTime.getDayOfWeek(maturity) == DateTime.DOW_FRI;
    }

    function isLastFriday(uint64 maturity) internal pure returns (bool) {
        uint256 dayOfMonth = DateTime.getDay(maturity);
        uint256 lastDayOfMonth = DateTime.getDaysInMonth(maturity);

        if (lastDayOfMonth - dayOfMonth > 7) return false;
        return isFriday(maturity);
    }

    function calculateTimeToMaturity(
        uint64 maturity
    ) internal view returns (uint256) {
        return maturity - block.timestamp;
    }

    function calculateStrikeInterval(
        int256 spot
    ) internal pure returns (int256) {
        SD59x18 NEG_ONE_59X18 = wrap(-1e18);
        SD59x18 ONE_59X18 = wrap(1e18);

        SD59x18 FIVE_59X18 = wrap(5e18);
        SD59x18 TEN_59X18 = wrap(10e18);

        SD59x18 SPOT_59X18 = wrap(spot);

        SD59x18 o = floor(log10(SPOT_59X18));
        SD59x18 x = SPOT_59X18.mul(
            pow(TEN_59X18, o.mul(NEG_ONE_59X18).sub(ONE_59X18))
        );

        SD59x18 f = pow(TEN_59X18, o.sub(ONE_59X18));
        SD59x18 y = x.lt(wrap(0.5e18)) ? mul(ONE_59X18, f) : mul(FIVE_59X18, f);
        return unwrap(SPOT_59X18.lt(wrap(1000e18)) ? y : ceil(y));
    }
}
