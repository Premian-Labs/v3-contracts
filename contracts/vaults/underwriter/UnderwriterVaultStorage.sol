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
        // ERC20 token address for the base asset
        address base;
        // ERC20 token address for the quote asset
        address quote;
        // Address for the oracle adapter to get spot prices for base/quote
        address oracleAdapter;
        // Whether the vault is underwriting calls or puts
        bool isCall;
        // The total assets that have been locked up as collateral for
        // underwritten options.
        uint256 totalLockedAssets;
        // Trading Parameters
        // Minimum days until maturity which can be underwritten by the vault, default 3
        uint256 minDTE;
        // Maximum days until maturity which can be underwritten by the vault, default 30
        uint256 maxDTE;
        // Minimum option delta which can be underwritten by the vault, default 0.1
        int256 minDelta;
        // Maximum option delta which can be underwritten by the vault, default 0.7
        int256 maxDelta;
        // C-Level Parameters
        uint256 minCLevel; // 1
        uint256 maxCLevel; // 1.2
        uint256 alphaCLevel; // 3
        uint256 hourlyDecayDiscount; // 0.005
        uint256 lastTradeTimestamp;
        // Data structures for information on listings
        // (strike, maturity) => number of short contracts
        mapping(uint256 => mapping(uint256 => uint256)) positionSizes;
        // The minimum maturity over all unsettled options
        uint256 minMaturity;
        // The maximum maturity over all unsettled options
        uint256 maxMaturity;
        // A SortedDoublyLinkedList for maturities
        DoublyLinkedList.Uint256List maturities;
        // maturity => set of strikes
        mapping(uint256 => EnumerableSet.UintSet) maturityToStrikes;
        // Variables for dispersing profits across time
        // Tracks the total profits/spreads that are locked such that we can
        // deduct it from the total assets
        uint256 totalLockedSpread;
        // Tracks the rate at which ask spreads are dispersed
        uint256 spreadUnlockingRate;
        // Tracks the time spreadUnlockingRate was updated
        uint256 lastSpreadUnlockUpdate;
        // we map maturities to the unlockingRate that needs to be deducted upon crossing
        // maturity => spreadUnlockingRate
        mapping(uint256 => uint256) spreadUnlockingTicks;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
