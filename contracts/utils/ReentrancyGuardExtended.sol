// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ReentrancyGuardStorage} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuardStorage.sol";

import {IReentrancyGuardExtended} from "./IReentrancyGuardExtended.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ReentrancyGuardExtendedStorage} from "./ReentrancyGuardExtendedStorage.sol";

contract ReentrancyGuardExtended is IReentrancyGuardExtended, OwnableInternal, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    modifier nonReentrant() override {
        bool locked = _lockReentrancyGuard(msg.data);
        _;
        if (locked) _unlockReentrancyGuard();
    }

    /// @inheritdoc IReentrancyGuardExtended
    function getReentrancyGuardSelectorsIgnored() external view returns (bytes4[] memory selectorsIgnored) {
        bytes32[] memory _selectorsIgnored = ReentrancyGuardExtendedStorage.layout().selectorsIgnored.toArray();
        uint256 length = _selectorsIgnored.length;
        selectorsIgnored = new bytes4[](length);

        for (uint256 i = 0; i < length; i++) {
            selectorsIgnored[i] = bytes4(_selectorsIgnored[i]);
        }
    }

    /// @inheritdoc IReentrancyGuardExtended
    function addReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardExtendedStorage.Layout storage l = ReentrancyGuardExtendedStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.add(bytes32(selectorsIgnored[i]));
            emit AddReentrancyGuardSelectorIgnored(selectorsIgnored[i]);
        }
    }

    /// @inheritdoc IReentrancyGuardExtended
    function removeReentrancyGuardSelectorsIgnored(bytes4[] memory selectorsIgnored) external onlyOwner {
        ReentrancyGuardExtendedStorage.Layout storage l = ReentrancyGuardExtendedStorage.layout();
        for (uint256 i = 0; i < selectorsIgnored.length; i++) {
            l.selectorsIgnored.remove(bytes32(selectorsIgnored[i]));
            emit RemoveReentrancyGuardSelectorIgnored(selectorsIgnored[i]);
        }
    }

    /// @inheritdoc IReentrancyGuardExtended
    function setReentrancyGuardDisabled(bool disabled) external onlyOwner {
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

    /// @notice Sets the reentrancy guard status to locked and returns true if the guard is not locked, overridden, nor
    ///         is the call static
    function _lockReentrancyGuard(bytes memory msgData) internal virtual returns (bool) {
        ReentrancyGuardExtendedStorage.Layout storage le = ReentrancyGuardExtendedStorage.layout();
        if (le.disabled) return false;
        if (le.selectorsIgnored.contains(bytes32(_getFunctionSelector(msgData)))) return false;

        ReentrancyGuardStorage.Layout storage l = ReentrancyGuardStorage.layout();
        if (l.status == REENTRANCY_STATUS_LOCKED) revert ReentrancyGuard__ReentrantCall();
        if (_isStaticCall()) return false;

        l.status = REENTRANCY_STATUS_LOCKED;
        return true;
    }

    /// @notice Sets the reentrancy guard status to unlocked
    function _unlockReentrancyGuard() internal virtual override {
        ReentrancyGuardStorage.layout().status = REENTRANCY_STATUS_UNLOCKED;
    }

    /// @notice Returns the derived function selector from the provided `msgData`
    function _getFunctionSelector(bytes memory msgData) private pure returns (bytes4 selector) {
        for (uint i = 0; i < 4; i++) {
            selector |= bytes4(msgData[i] & 0xFF) >> (i * 8);
        }
    }
}
