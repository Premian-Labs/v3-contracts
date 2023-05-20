// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPricing {
    error Pricing__PriceCannotBeComputedWithinTickRange();
    error Pricing__PriceOutOfRange(
        UD60x18 lower,
        UD60x18 upper,
        UD60x18 marketPrice
    );
    error Pricing__UpperNotGreaterThanLower(UD60x18 lower, UD60x18 upper);
}
