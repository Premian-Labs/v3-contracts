// SPDX-License-Identifier: LGPL-3.0-or-later

pragma solidity ^0.8.0;

interface IPoolInternal {
    error Pool__ZeroSize();
    error Pool__ExpiredOption();
    error Pool__InvalidTickWidth();
    error Pool__BuyPositionBelowMarketPrice();
    error Pool__SellPositionAboveMarketPrice();
}
