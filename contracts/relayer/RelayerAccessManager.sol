// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IRelayerAccessManager} from "./IRelayerAccessManager.sol";
import {RelayerAccessManagerStorage} from "./RelayerAccessManagerStorage.sol";

abstract contract RelayerAccessManager is IRelayerAccessManager, OwnableInternal, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IRelayerAccessManager
    function addWhitelistedRelayers(address[] calldata relayers) external virtual onlyOwner nonReentrant {
        RelayerAccessManagerStorage.Layout storage l = RelayerAccessManagerStorage.layout();

        for (uint256 i = 0; i < relayers.length; i++) {
            if (l.whitelistedRelayers.add(relayers[i])) {
                emit AddWhitelistedRelayer(relayers[i]);
            }
        }
    }

    /// @inheritdoc IRelayerAccessManager
    function removeWhitelistedRelayers(address[] calldata relayers) external virtual onlyOwner nonReentrant {
        RelayerAccessManagerStorage.Layout storage l = RelayerAccessManagerStorage.layout();

        for (uint256 i = 0; i < relayers.length; i++) {
            if (l.whitelistedRelayers.remove(relayers[i])) {
                emit RemoveWhitelistedRelayer(relayers[i]);
            }
        }
    }

    /// @inheritdoc IRelayerAccessManager
    function getWhitelistedRelayers() external view virtual returns (address[] memory relayers) {
        relayers = RelayerAccessManagerStorage.layout().whitelistedRelayers.toArray();
    }

    /// @notice Revert if `relayer` is not whitelisted
    function _revertIfNotWhitelistedRelayer(address relayer) internal view {
        if (!RelayerAccessManagerStorage.layout().whitelistedRelayers.contains(relayer))
            revert RelayerAccessManager__NotWhitelistedRelayer(relayer);
    }
}
