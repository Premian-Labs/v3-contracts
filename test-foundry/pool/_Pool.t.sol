// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolSwapAndDepositTest} from "./Pool.swapAndDeposit.t.sol";
import {PoolSwapAndTradeTest} from "./Pool.swapAndTrade.t.sol";
import {PoolTradeTest} from "./Pool.trade.t.sol";
import {PoolTradeAndSwapTest} from "./Pool.tradeAndSwap.t.sol";

abstract contract PoolTest is
    PoolDepositTest,
    PoolSwapAndDepositTest,
    PoolSwapAndTradeTest,
    PoolTradeTest,
    PoolTradeAndSwapTest
{}
