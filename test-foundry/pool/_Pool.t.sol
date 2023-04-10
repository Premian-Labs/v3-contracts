// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolFillQuoteTest} from "./Pool.fillQuote.t.sol";
import {PoolTradeTest} from "./Pool.trade.t.sol";
import {PoolWithdrawTest} from "./Pool.withdraw.t.sol";
import {PoolStrandedTest} from "./Pool.stranded.t.sol";

abstract contract PoolTest is
    PoolDepositTest,
    PoolFillQuoteTest,
    PoolStrandedTest,
    PoolTradeTest,
    PoolWithdrawTest
{}
