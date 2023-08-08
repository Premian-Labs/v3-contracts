// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";

import {IVault} from "../../IVault.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../libraries/EnumerableSetUD60x18.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";

library UnderwriterVaultStorage {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;

    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.UnderwriterVaultStorage");

    struct Layout {
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Vault Specification
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // ERC20 token address for the base asset
        address base;
        // ERC20 token address for the quote asset
        address quote;
        // Base precision
        uint8 baseDecimals;
        // Quote precision
        uint8 quoteDecimals;
        // Address for the oracle adapter to get spot prices for base/quote
        address oracleAdapter;
        // Whether the vault is underwriting calls or puts
        bool isCall;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Vault Accounting
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // The total assets held in the vault from deposits
        UD60x18 totalAssets;
        // The total assets that have been locked up as collateral for underwritten options.
        UD60x18 totalLockedAssets;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Trading Parameters
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Minimum days until maturity which can be underwritten by the vault, default 3
        UD60x18 minDTE;
        // Maximum days until maturity which can be underwritten by the vault, default 30
        UD60x18 maxDTE;
        // Minimum option delta which can be underwritten by the vault, default 0.1
        UD60x18 minDelta;
        // Maximum option delta which can be underwritten by the vault, default 0.7
        UD60x18 maxDelta;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // C-Level Parameters
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        UD60x18 minCLevel; // 1
        UD60x18 maxCLevel; // 1.2
        UD60x18 alphaCLevel; // 3
        UD60x18 hourlyDecayDiscount; // 0.005
        uint256 lastTradeTimestamp;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Data structures for information on listings
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // The minimum maturity over all unsettled options
        uint256 minMaturity;
        // The maximum maturity over all unsettled options
        uint256 maxMaturity;
        // A SortedDoublyLinkedList for maturities
        DoublyLinkedList.Uint256List maturities;
        // maturity => set of strikes
        mapping(uint256 => EnumerableSet.Bytes32Set) maturityToStrikes;
        // (maturity, strike) => number of short contracts
        mapping(uint256 => mapping(UD60x18 => UD60x18)) positionSizes;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Dispersing Profit Variables
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Tracks the total profits/spreads that are locked such that we can deduct it from the total assets
        UD60x18 totalLockedSpread;
        // Tracks the rate at which ask spreads are dispersed
        UD60x18 spreadUnlockingRate;
        // Tracks the time spreadUnlockingRate was updated
        uint256 lastSpreadUnlockUpdate;
        // Tracks the unlockingRate for maturities that need to be deducted upon crossing
        // maturity => spreadUnlockingRate
        mapping(uint256 => UD60x18) spreadUnlockingTicks;
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        // Management/Performance Fee Variables
        // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        UD60x18 managementFeeRate;
        UD60x18 performanceFeeRate;
        UD60x18 protocolFees;
        uint256 lastManagementFeeTimestamp;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function updateSettings(Layout storage l, bytes memory settings) internal {
        // Handle decoding of settings and updating storage
        if (settings.length == 0) revert IVault.Vault__SettingsUpdateIsEmpty();

        UD60x18[] memory arr = abi.decode(settings, (UD60x18[]));

        l.alphaCLevel = arr[0];
        l.hourlyDecayDiscount = arr[1];
        l.minCLevel = arr[2];
        l.maxCLevel = arr[3];
        l.minDTE = arr[4];
        l.maxDTE = arr[5];
        l.minDelta = arr[6];
        l.maxDelta = arr[7];
        l.performanceFeeRate = arr[8];
        l.managementFeeRate = arr[9];
    }

    function assetDecimals(Layout storage l) internal view returns (uint8) {
        return l.isCall ? l.baseDecimals : l.quoteDecimals;
    }

    function collateral(Layout storage l, UD60x18 size, UD60x18 strike) internal view returns (UD60x18) {
        return l.isCall ? size : size * strike;
    }

    function convertAssetToUD60x18(Layout storage l, uint256 value) internal view returns (UD60x18) {
        return UD60x18.wrap(OptionMath.scaleDecimals(value, l.assetDecimals(), 18));
    }

    function convertAssetFromUD60x18(Layout storage l, UD60x18 value) internal view returns (uint256) {
        return OptionMath.scaleDecimals(value.unwrap(), 18, l.assetDecimals());
    }

    /// @notice Gets the nearest maturity after the given timestamp, exclusive
    ///         of the timestamp being on a maturity
    /// @param timestamp The given timestamp
    /// @return The nearest maturity after the given timestamp
    function getMaturityAfterTimestamp(Layout storage l, uint256 timestamp) internal view returns (uint256) {
        uint256 current = l.minMaturity;

        while (current <= timestamp && current != 0) {
            current = l.maturities.next(current);
        }
        return current;
    }

    /// @notice Gets the number of unexpired listings within the basket of
    ///         options underwritten by this vault at the current time
    /// @param timestamp The given timestamp
    /// @return The number of unexpired listings
    function getNumberOfUnexpiredListings(Layout storage l, uint256 timestamp) internal view returns (uint256) {
        uint256 n = 0;

        if (l.maxMaturity <= timestamp) return 0;

        uint256 current = l.getMaturityAfterTimestamp(timestamp);

        while (current <= l.maxMaturity && current != 0) {
            n += l.maturityToStrikes[current].length();
            current = l.maturities.next(current);
        }

        return n;
    }

    /// @notice Checks if a listing exists within internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
    /// @return If listing exists, return true, false otherwise
    function contains(Layout storage l, UD60x18 strike, uint256 maturity) internal view returns (bool) {
        if (!l.maturities.contains(maturity)) return false;

        return l.maturityToStrikes[maturity].contains(strike);
    }

    /// @notice Adds a listing to the internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
    function addListing(Layout storage l, UD60x18 strike, uint256 maturity) internal {
        // Insert maturity if it doesn't exist
        if (!l.maturities.contains(maturity)) {
            if (maturity < l.minMaturity) {
                l.maturities.insertBefore(l.minMaturity, maturity);
                l.minMaturity = maturity;
            } else if ((l.minMaturity < maturity) && (maturity) < l.maxMaturity) {
                uint256 next = l.getMaturityAfterTimestamp(maturity);
                l.maturities.insertBefore(next, maturity);
            } else {
                l.maturities.insertAfter(l.maxMaturity, maturity);

                if (l.minMaturity == 0) l.minMaturity = maturity;

                l.maxMaturity = maturity;
            }
        }

        // Insert strike into the set of strikes for given maturity
        if (!l.maturityToStrikes[maturity].contains(strike)) l.maturityToStrikes[maturity].add(strike);
    }

    /// @notice Removes a listing from internal data structures
    /// @param strike The strike price of the listing
    /// @param maturity The maturity of the listing
    function removeListing(Layout storage l, UD60x18 strike, uint256 maturity) internal {
        if (l.contains(strike, maturity)) {
            l.maturityToStrikes[maturity].remove(strike);

            // Remove maturity if there are no strikes left
            if (l.maturityToStrikes[maturity].length() == 0) {
                if (maturity == l.minMaturity) l.minMaturity = l.maturities.next(maturity);
                if (maturity == l.maxMaturity) l.maxMaturity = l.maturities.prev(maturity);

                l.maturities.remove(maturity);
            }
        }
    }
}
