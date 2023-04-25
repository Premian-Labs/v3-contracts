// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolExerciseTest} from "./Pool.exercise.t.sol";
import {PoolFillQuoteRFQTest} from "./Pool.fillQuoteRFQ.t.sol";
import {PoolSettleTest} from "./Pool.settle.t.sol";
import {PoolStrandedTest} from "./Pool.stranded.t.sol";
import {PoolTradeTest} from "./Pool.trade.t.sol";
import {PoolWithdrawTest} from "./Pool.withdraw.t.sol";

abstract contract PoolTest is
    PoolDepositTest,
    PoolExerciseTest,
    PoolFillQuoteRFQTest,
    PoolStrandedTest,
    PoolSettleTest,
    PoolTradeTest,
    PoolWithdrawTest
{}
