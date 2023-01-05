// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {_IPoolMock} from "./_IPoolMock.sol";
import {IPool} from "../pool/IPool.sol";

interface IPoolMock is _IPoolMock, IPool {}
