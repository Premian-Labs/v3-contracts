// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
//import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {ReentrancyGuardStorage} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuardStorage.sol";

import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ReentrancyGuardExtendedStorage} from "./ReentrancyGuardExtendedStorage.sol";

contract ReentrancyGuardExtended is OwnableInternal, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using ReentrancyGuardStorage for ReentrancyGuardStorage.Layout;
    using ReentrancyGuardExtendedStorage for ReentrancyGuardExtendedStorage.Layout;

    // TODO: getter for disabled
    // TODO: getter for selectorsIgnored

    modifier nonReentrant() override {
        bool locked = _lockReentrancyGuard(msg.data);
        _;
        if (locked) _unlockReentrancyGuard();
    }

    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardExtendedStorage.Layout storage l = ReentrancyGuardExtendedStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.add(bytes32(selectorsIgnored[i]));
        }
    }

    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardExtendedStorage.Layout storage l = ReentrancyGuardExtendedStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.remove(bytes32(selectorsIgnored[i]));
        }
    }

    function setReentrancyGuardDisabled(bool disabled) external onlyOwner {
        ReentrancyGuardExtendedStorage.layout().disabled = disabled;
    }

    function _lockReentrancyGuard(bytes memory msgData) internal virtual returns (bool) {
        ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();
        if (l.status == REENTRANCY_STATUS_LOCKED) revert ReentrancyGuard__ReentrantCall();

        ReentrancyGuardExtendedStorage.Layout storage le = ReentrancyGuardExtendedStorage.layout();
        if (le.selectorsIgnored.contains(bytes32(_getFunctionSelector(msgData)))) return false;
        if (le.disabled) return false;

        l.status = REENTRANCY_STATUS_LOCKED;
        return true;
    }

    function _unlockReentrancyGuard() internal virtual override {
        ReentrancyGuardStorage.layout().status = REENTRANCY_STATUS_UNLOCKED;
    }

    function _getFunctionSelector(bytes memory msgData) private pure returns (bytes4 selector) {
        for (uint i = 0; i < 4; i++) {
            selector |= bytes4(msgData[i] & 0xFF) >> (i * 8);
        }
    }
}
