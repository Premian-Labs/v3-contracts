// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolCore} from "./IPoolCore.sol";
import {IPoolDepositWithdraw} from "./IPoolDepositWithdraw.sol";
import {IPoolTrade} from "./IPoolTrade.sol";
import {IPoolEvents} from "./IPoolEvents.sol";

interface IPool is IPoolBase, IPoolCore, IPoolDepositWithdraw, IPoolEvents, IPoolTrade {}
