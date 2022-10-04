// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PoolInternal} from "./PoolInternal.sol";
import {PoolStorage} from "./PoolStorage.sol";

contract Pool is PoolInternal {
    function deposit(
        address owner,
        PoolStorage.Side rangeSide,
        uint256 lower,
        uint256 upper,
        uint256 collateral,
        uint256 contracts
    ) external {
        //        _deposit();
    }
}
