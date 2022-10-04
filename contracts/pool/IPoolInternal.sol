// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolInternal {
    error Pool__BuyPositionBelowMarketPrice();
    error Pool__ExpiredOption();
    error Pool__TickInsertFailed();
    error Pool__TickInsertInvalid();
    error Pool__TickInsertInvalidLocation();
    error Pool__TickWidthInvalid();
    error Pool__SellPositionAboveMarketPrice();
    error Pool__ZeroSize();
}
