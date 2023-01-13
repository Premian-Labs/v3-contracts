// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPoolCoreMock} from "./IPoolCoreMock.sol";
import {IPool} from "../../pool/IPool.sol";

interface IPoolMock is IPoolCoreMock, IPool {}
