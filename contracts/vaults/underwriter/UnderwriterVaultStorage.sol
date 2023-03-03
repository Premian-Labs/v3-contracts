// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

library UnderwriterVaultStorage {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeCast for int256;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.UnderwriterVaultStorage");

    struct Layout {
        address base;
        address quote;
        address oracleAdapter;
        // Whether the vault is underwriting calls or puts
        bool isCall;
        // The total assets that have been included in the pool.
        uint256 totalAssets;
        uint256 totalLockedAssets;
        // Trading Parameters
        uint256 maxDTE; // 30
        uint256 minDTE; // 3
        int256 minDelta; // 0.10
        int256 maxDelta; // 0.70
        // C-Level Parameters
        uint256 minCLevel; // 1
        uint256 maxCLevel; // 1.2
        uint256 alphaCLevel; // 3
        uint256 hourlyDecayDiscount; // 0.005
        uint256 lastTradeTimestamp;
        // (strike, maturity) => number of short contracts
        mapping(uint256 => mapping(uint256 => uint256)) positionSizes;
        // SortedLinkedList for maturities
        uint256 minMaturity;
        uint256 maxMaturity;
        DoublyLinkedList.Uint256List maturities;
        // maturity => set of strikes
        mapping(uint256 => EnumerableSet.UintSet) maturityToStrikes;
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
