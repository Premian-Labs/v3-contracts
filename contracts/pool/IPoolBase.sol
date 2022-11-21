// SPDX-License-Identifier: UNLICENSED



pragma solidity ^0.8.0;

interface IPoolBase {
    /**
     * @notice get token collection name
     * @return collection name
     */
    function name() external view returns (string memory);
}
