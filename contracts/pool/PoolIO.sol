// SPDX-License-Identifier: UNLICENSED



// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {IPoolIO} from "./IPoolIO.sol";
import {PoolInternal} from "./PoolInternal.sol";

contract PoolIO is IPoolIO, PoolInternal {}
