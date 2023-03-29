// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {PoolDepositTest} from "./Pool.deposit.t.sol";
import {PoolSwapAndDepositTest} from "./Pool.swapAndDeposit.t.sol";

abstract contract PoolTest is PoolDepositTest, PoolSwapAndDepositTest {}
