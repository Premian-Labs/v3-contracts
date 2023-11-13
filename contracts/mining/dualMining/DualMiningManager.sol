// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {SafeOwnable, OwnableInternal} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {ProxyManager} from "../../proxy/ProxyManager.sol";

/// @notice Manages the proxy implementation of DualMining contracts
contract DualMiningManager is ProxyManager, SafeOwnable {
    constructor(address implementation) {
        _setOwner(msg.sender);
        _setManagedProxyImplementation(implementation);
    }

    function _transferOwnership(address account) internal virtual override(OwnableInternal, SafeOwnable) {
        super._transferOwnership(account);
    }
}
