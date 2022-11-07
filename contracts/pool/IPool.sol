// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolBase} from "./IPoolBase.sol";
import {IPoolIO} from "./IPoolIO.sol";

interface IPool is IPoolBase, IPoolIO {}
