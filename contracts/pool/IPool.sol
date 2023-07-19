// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolCore} from "./IPoolCore.sol";
import {IPoolDepositWithdraw} from "./IPoolDepositWithdraw.sol";
import {IPoolTrade} from "./IPoolTrade.sol";
import {IPoolEvents} from "./IPoolEvents.sol";

interface IPool is IPoolBase, IPoolCore, IPoolDepositWithdraw, IPoolEvents, IPoolTrade {}
