// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/IReentrancyGuard.sol";
import {ReentrancyGuardStorage} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuardStorage.sol";

/// @title Utility contract for preventing reentrancy attacks
abstract contract ReentrancyGuard is IReentrancyGuard {
    uint256 internal constant REENTRANCY_STATUS_LOCKED = 2;
    uint256 internal constant REENTRANCY_STATUS_UNLOCKED = 1;

    modifier nonReentrant() virtual {
        if (ReentrancyGuardStorage.layout().status == REENTRANCY_STATUS_LOCKED) revert ReentrancyGuard__ReentrantCall();
        _lockReentrancyGuard();
        _;
        _unlockReentrancyGuard();
    }

    /// @notice lock functions that use the nonReentrant modifier
    function _lockReentrancyGuard() internal virtual {
        ReentrancyGuardStorage.layout().status = REENTRANCY_STATUS_LOCKED;
    }

    /// @notice unlock functions that use the nonReentrant modifier
    function _unlockReentrancyGuard() internal virtual {
        ReentrancyGuardStorage.layout().status = REENTRANCY_STATUS_UNLOCKED;
    }
}
