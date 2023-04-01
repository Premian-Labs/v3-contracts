// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolFillQuoteTest} from "./Pool.fillQuote.t.sol";
import {PoolTradeTest} from "./Pool.trade.t.sol";

abstract contract PoolTest is
    PoolDepositTest,
    PoolFillQuoteTest,
    PoolTradeTest
{}
