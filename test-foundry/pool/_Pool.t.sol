// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolExerciseTest} from "./Pool.exercise.t.sol";
import {PoolFillQuoteRFQTest} from "./Pool.fillQuoteRFQ.t.sol";
import {PoolFlashLoanTest} from "./Pool.flashLoan.t.sol";
import {PoolSettleTest} from "./Pool.settle.t.sol";
import {PoolSettlePositionTest} from "./Pool.settlePosition.t.sol";
import {PoolStrandedTest} from "./Pool.stranded.t.sol";
import {PoolTakerFeeTest} from "./Pool.takerFee.t.sol";
import {PoolTradeTest} from "./Pool.trade.t.sol";
import {PoolTransferTest} from "./Pool.transfer.t.sol";
import {PoolWithdrawTest} from "./Pool.withdraw.t.sol";

abstract contract PoolTest is
    PoolDepositTest,
    PoolExerciseTest,
    PoolFillQuoteRFQTest,
    PoolFlashLoanTest,
    PoolSettleTest,
    PoolSettlePositionTest,
    PoolStrandedTest,
    PoolTakerFeeTest,
    PoolTradeTest,
    PoolTransferTest,
    PoolWithdrawTest
{}
