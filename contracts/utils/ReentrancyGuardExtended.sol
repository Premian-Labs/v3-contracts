// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuardStorage} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuardStorage.sol";

import {IReentrancyGuardExtended} from "./IReentrancyGuardExtended.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ReentrancyGuardExtendedStorage} from "./ReentrancyGuardExtendedStorage.sol";

contract ReentrancyGuardExtended is IReentrancyGuardExtended, OwnableInternal, ReentrancyGuard {
    modifier nonReentrant() virtual override {
        bool isDisabled = _isReentrancyGuardDisabled();

        bool isStaticCall;
        if (!isDisabled) {
            ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();
            if (l.status == REENTRANCY_STATUS_LOCKED) revert ReentrancyGuard__ReentrantCall();
            isStaticCall = _isStaticCall();
            if (!isStaticCall) _lockReentrancyGuard();
        }
        _;
        if (!isDisabled && !isStaticCall) _unlockReentrancyGuard();
    }

    /// @notice Returns true if the reentrancy guard is disabled, false otherwise
    function _isReentrancyGuardDisabled() internal view virtual returns (bool) {
        return ReentrancyGuardExtendedStorage.layout().disabled;
    }

    /// @inheritdoc IReentrancyGuardExtended
    function setReentrancyGuardDisabled(bool disabled) external virtual onlyOwner {
        ReentrancyGuardExtendedStorage.layout().disabled = disabled;
        emit SetReentrancyGuardDisabled(disabled);
    }

    /// @notice Triggers a static-call check
    /// @dev For internal use only
    function __staticCallCheck() external {
        emit ReentrancyStaticCallCheck();
    }

    /// @notice Initiates an external call to `this` to determine if the current call is static
    function _isStaticCall() internal returns (bool) {
        try this.__staticCallCheck() {
            return false;
        } catch {
            return true;
        }
    }
}
