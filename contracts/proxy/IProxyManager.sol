// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IProxyManager {
    function getManagedProxyImplementation() external view returns (address);

    function setManagedProxyImplementation(address implementation) external;
}
