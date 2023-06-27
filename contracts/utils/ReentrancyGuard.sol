// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";

import {ReentrancyGuardStorage} from "./ReentrancyGuardStorage.sol";

contract ReentrancyGuard is OwnableInternal {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using ReentrancyGuardStorage for ReentrancyGuardStorage.Layout;

    error ReentrancyGuard__ReentrantCall();

    uint256 internal constant REENTRANCY_STATUS_LOCKED = 2;
    uint256 internal constant REENTRANCY_STATUS_UNLOCKED = 1;

    modifier nonReentrant() {
        bool locked = _lockReentrancyGuard(msg.data);
        _;
        if (locked) _unlockReentrancyGuard();
    }

    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.add(bytes32(selectorsIgnored[i]));
        }
    }

    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.remove(bytes32(selectorsIgnored[i]));
        }
    }

    function setReentrancyGuardDisabled(bool disabled) external onlyOwner {
        ReentrancyGuardStorage.layout().disabled = disabled;
    }

    function _lockReentrancyGuard(bytes memory msgData) internal returns (bool) {
        ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();

        if (l.reentrancyStatus == REENTRANCY_STATUS_LOCKED) revert ReentrancyGuard__ReentrantCall();
        if (l.selectorsIgnored.contains(bytes32(_getFunctionSelector(msgData)))) return false;
        if (l.disabled) return false;

        l.reentrancyStatus = REENTRANCY_STATUS_LOCKED;
        return true;
    }

    function _unlockReentrancyGuard() internal {
        ReentrancyGuardStorage.layout().reentrancyStatus = REENTRANCY_STATUS_UNLOCKED;
    }

    function _getFunctionSelector(bytes memory msgData) internal pure returns (bytes4 selector) {
        for (uint i = 0; i < 4; i++) {
            selector |= bytes4(msgData[i] & 0xFF) >> (i * 8);
        }
    }
}
