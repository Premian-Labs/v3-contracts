// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolCore} from "./IPoolCore.sol";
import {IPoolBase} from "./IPoolBase.sol";

interface IPool is IPoolCore, IPoolBase {}
