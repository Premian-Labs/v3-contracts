// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ProxyUpgradeableOwnable} from "./ProxyUpgradeableOwnable.sol";

import {ReentrancyGuard} from "../utils/ReentrancyGuard.sol";

contract ProxyUpgradeableOwnableNonReentrant is ProxyUpgradeableOwnable, ReentrancyGuard {
    using AddressUtils for address;

    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {}

    function _delegateCalls() internal override nonReentrant {
        super._delegateCalls();
    }

    function _transferOwnership(address account) internal virtual override(SafeOwnable, OwnableInternal) {
        SafeOwnable._transferOwnership(account);
    }
}
