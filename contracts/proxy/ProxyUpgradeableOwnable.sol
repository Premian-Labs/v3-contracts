// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {ProxyUpgradeableOwnableStorage} from "./ProxyUpgradeableOwnableStorage.sol";

contract ProxyUpgradeableOwnable is Proxy, SafeOwnable {
    using AddressUtils for address;

    event ImplementationSet(address implementation);

    error ProxyUpgradeableOwnable__InvalidImplementation(address implementation);

    constructor(address implementation) {
        _setOwner(msg.sender);
        _setImplementation(implementation);
    }

    receive() external payable {}

    /// @inheritdoc Proxy
    function _getImplementation() internal view override returns (address) {
        return ProxyUpgradeableOwnableStorage.layout().implementation;
    }

    /// @notice get address of implementation contract
    /// @return implementation address
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /// @notice set address of implementation contract
    /// @param implementation address of the new implementation
    function setImplementation(address implementation) external onlyOwner {
        _setImplementation(implementation);
    }

    /// @notice set address of implementation contract
    function _setImplementation(address implementation) internal {
        if (!implementation.isContract()) revert ProxyUpgradeableOwnable__InvalidImplementation(implementation);

        ProxyUpgradeableOwnableStorage.layout().implementation = implementation;
        emit ImplementationSet(implementation);
    }
}
