// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";

import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../libraries/EnumerableSetUD60x18.sol";

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
        UD60x18 totalLockedAssets;
        // Trading Parameters
        // Minimum days until maturity which can be underwritten by the vault, default 3
        UD60x18 minDTE;
        // Maximum days until maturity which can be underwritten by the vault, default 30
        UD60x18 maxDTE;
        // Minimum option delta which can be underwritten by the vault, default 0.1
        SD59x18 minDelta;
        // Maximum option delta which can be underwritten by the vault, default 0.7
        SD59x18 maxDelta;
        // C-Level Parameters
        UD60x18 minCLevel; // 1
        UD60x18 maxCLevel; // 1.2
        UD60x18 alphaCLevel; // 3
        UD60x18 hourlyDecayDiscount; // 0.005
        UD60x18 lastTradeTimestamp;
        // Data structures for information on listings
        // (strike, maturity) => number of short contracts
        mapping(UD60x18 => mapping(UD60x18 => UD60x18)) positionSizes;
        // The minimum maturity over all unsettled options
        UD60x18 minMaturity;
        // The maximum maturity over all unsettled options
        UD60x18 maxMaturity;
        // A SortedDoublyLinkedList for maturities
        DoublyLinkedList.Bytes32List maturities;
        // maturity => set of strikes
        mapping(UD60x18 => EnumerableSet.Bytes32Set) maturityToStrikes;
        // Variables for dispersing profits across time
        // Tracks the total profits/spreads that are locked such that we can
        // deduct it from the total assets
        UD60x18 totalLockedSpread;
        // Tracks the rate at which ask spreads are dispersed
        UD60x18 spreadUnlockingRate;
        // Tracks the time spreadUnlockingRate was updated
        UD60x18 lastSpreadUnlockUpdate;
        // we map maturities to the unlockingRate that needs to be deducted upon crossing
        // maturity => spreadUnlockingRate
        mapping(UD60x18 => UD60x18) spreadUnlockingTicks;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
