// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ProxyUpgradeableOwnable} from "./ProxyUpgradeableOwnable.sol";

import {ReentrancyGuardExtended} from "../utils/ReentrancyGuardExtended.sol";

contract ProxyUpgradeableOwnableNonReentrant is ProxyUpgradeableOwnable, ReentrancyGuardExtended {
    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {}

    function _handleDelegateCalls() internal override nonReentrant returns (bool result, bytes memory data) {
        return super._handleDelegateCalls();
    }

    function _transferOwnership(address account) internal virtual override(SafeOwnable, OwnableInternal) {
        SafeOwnable._transferOwnership(account);
    }
}
