// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IPool} from "contracts/pool/IPool.sol";

import {IPoolCoreMock} from "./IPoolCoreMock.sol";

interface IPoolMock is IPool, IPoolCoreMock {}
