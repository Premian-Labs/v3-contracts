// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ReentrancyGuardStorage} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuardStorage.sol";

import {ProxyUpgradeableOwnableNonReentrant} from "../../proxy/ProxyUpgradeableOwnableNonReentrant.sol";
import {ReentrancyGuardExtendedStorage} from "../../utils/ReentrancyGuardExtendedStorage.sol";

contract ProxyUpgradeableOwnableNonReentrantMock is ProxyUpgradeableOwnableNonReentrant {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    constructor(address implementation) ProxyUpgradeableOwnableNonReentrant(implementation) {}

    function __lockReentrancyGuard() external {
        _lockReentrancyGuard(msg.data);
    }

    function __unlockReentrancyGuard() external {
        _unlockReentrancyGuard();
    }

    function isReentrancyGuardLocked() external view returns (bool) {
        return ReentrancyGuardStorage.layout().status == REENTRANCY_STATUS_LOCKED;
    }

    function isReentrancyGuardDisabled() external view returns (bool) {
        return ReentrancyGuardExtendedStorage.layout().disabled;
    }
}
