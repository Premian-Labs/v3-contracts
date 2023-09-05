// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IProxyUpgradeableOwnable {
    /// @notice Return the implementation address of the proxy
    function getImplementation() external view returns (address);
}
