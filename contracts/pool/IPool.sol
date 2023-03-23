// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {IPoolTrade} from "./IPoolTrade.sol";
import {IPoolCore} from "./IPoolCore.sol";
import {IPoolBase} from "./IPoolBase.sol";
import {IPoolEvents} from "./IPoolEvents.sol";

interface IPool is IPoolTrade, IPoolCore, IPoolBase, IPoolEvents {}
