// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPricing {
    error Pricing__PriceCannotBeComputedWithinTickRange();
    error Pricing__PriceOutOfRange();
    error Pricing__UpperNotGreaterThanLower();
}
