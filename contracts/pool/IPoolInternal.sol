// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolInternal {
    error Pool__BuyPositionBelowMarketPrice();
    error Pool__InsufficientWithdrawableBalance();
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__SellPositionAboveMarketPrice();
    error Pool__TickInsertFailed();
    error Pool__TickInsertInvalid();
    error Pool__TickInsertInvalidLocation();
    error Pool__TickNotFound();
    error Pool__TickWidthInvalid();
    error Pool__ZeroSize();
}
