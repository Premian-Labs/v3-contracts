// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IProxyManager {
    event ManagedImplementationSet(address implementation);

    /// @notice Return the implementation address of the managed proxy
    function getManagedProxyImplementation() external view returns (address);

    /// @notice Set the implementation address of the managed proxy
    function setManagedProxyImplementation(address implementation) external;
}
