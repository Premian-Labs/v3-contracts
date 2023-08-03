// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {PoolName} from "../../libraries/PoolName.sol";

contract PoolNameMock {
    function monthToString(uint256 month) external pure returns (string memory) {
        return PoolName.monthToString(month);
    }
}
