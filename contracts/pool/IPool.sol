// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolCore} from "./IPoolCore.sol";
import {IPoolBase} from "./IPoolBase.sol";
import {IPoolEvents} from "./IPoolEvents.sol";

interface IPool is IPoolCore, IPoolBase, IPoolEvents {}
