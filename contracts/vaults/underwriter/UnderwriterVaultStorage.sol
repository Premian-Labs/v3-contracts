// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

library UnderwriterVaultStorage {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeCast for int256;

    bytes32 internal constant STORAGE_SLOT =
    keccak256("premia.contracts.storage.UnderwriterVaultStorage");

    struct Layout {

        uint256 variable;

        address base;
        address quote;

        // Whether the vault is underwriting calls or puts
        bool isCall;

        // The total assets that have been included in the pool.
        uint256 totalAssets;
        uint256 totalLockedAssets;

        // (strike, maturity) => number of short contracts
        mapping(uint256 => mapping(uint256 => uint256)) positions;

        // supported maturities and strikes; these need to be managed by a keeper and can be updated whenever there is
        // a sufficiently large change in spot which would require underwriting new strikes
        mapping(uint256 => bool) supportedMaturities;
        mapping(uint256 => bool) supportedStrikes;

        // we need to manage a linked list in order to track what the next maturity such that we know when to decrement
        // the spreadUnlockingRate
        uint256 lastMaturity;
        mapping(uint256 => uint256) nextMaturities;

        // tracks the total profits / spreads that are locked such that we can deduct it from the total assets
        uint256 totalLockedSpread;
        // tracks the rate at which ask spreads are dispersed
        // why? the vault charges FV + spread, therefore the pps would increase.
        // this would allow
        uint256 spreadUnlockingRate;
        uint256 lastSpreadUnlockUpdate;
        // we map maturities to the unlockingRate that needs to be deducted upon crossing
        mapping(uint256 => uint256) spreadUnlockingTicks;

    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
