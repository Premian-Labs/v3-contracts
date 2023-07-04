// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IProxyUpgradeableOwnable {
    function getImplementation() external view returns (address);
}
