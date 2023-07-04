// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IPoolV2ProxyManager {
    function getPoolList() external view returns (address[] memory);
}
