// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation, which suppoprts access control multi-call and ERC165
abstract contract OracleAdapter is IOracleAdapter, Multicall {

}
