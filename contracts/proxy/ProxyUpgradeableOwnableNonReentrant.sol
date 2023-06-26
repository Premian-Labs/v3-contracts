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

    fallback() external payable override {
        bool locked = _lockReentrancyGuard(msg.data);

        //

        address implementation = _getImplementation();

        if (!implementation.isContract()) revert Proxy__ImplementationIsNotContract();

        bool result;
        assembly {
            calldatacopy(0, 0, calldatasize())
            result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
        }

        //

        if (locked) {
            _unlockReentrancyGuard();
        }

        //

        assembly {
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function _transferOwnership(address account) internal virtual override(SafeOwnable, OwnableInternal) {
        SafeOwnable._transferOwnership(account);
    }
}
