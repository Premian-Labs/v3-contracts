// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ProxyManagerStorage} from "./ProxyManagerStorage.sol";
import {IProxyManager} from "./IProxyManager.sol";

contract ProxyManager is IProxyManager, OwnableInternal {
    function getManagedProxyImplementation() external view returns (address) {
        return ProxyManagerStorage.layout().managedProxyImplementation;
    }

    function setManagedProxyImplementation(address implementation) external onlyOwner {
        ProxyManagerStorage.layout().managedProxyImplementation = implementation;
    }
}
