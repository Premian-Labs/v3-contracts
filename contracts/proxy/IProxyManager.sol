// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IProxyManager {
    function getManagedProxyImplementation() external view returns (address);

    function setManagedProxyImplementation(address implementation) external;
}
