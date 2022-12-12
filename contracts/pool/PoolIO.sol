// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolIO} from "./IPoolIO.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolIO is IPoolIO, PoolInternal {}
