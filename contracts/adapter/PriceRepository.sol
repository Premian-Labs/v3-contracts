// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepository is IPriceRepository, OwnableInternal {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc IPriceRepository
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external virtual {
        _revertIfWhitelistedRelayerNotAuthorized(msg.sender);
        PriceRepositoryStorage.layout().prices[base][quote][timestamp] = price;
        emit PriceUpdate(base, quote, timestamp, price);
    }

    /// @notice Returns the cached price at a given timestamp, if zero, a price has not been recorded
    function _getCachedPriceAt(address base, address quote, uint256 timestamp) internal view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().prices[base][quote][timestamp];
    }

    /// @inheritdoc IPriceRepository
    function addWhitelistedRelayers(address[] calldata relayers) external virtual onlyOwner {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();

        for (uint256 i = 0; i < relayers.length; i++) {
            if (l.whitelistedRelayers.add(relayers[i])) {
                emit AddWhitelistedRelayer(relayers[i]);
            }
        }
    }

    /// @inheritdoc IPriceRepository
    function removeWhitelistedRelayers(address[] calldata relayers) external virtual onlyOwner {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();

        for (uint256 i = 0; i < relayers.length; i++) {
            if (l.whitelistedRelayers.remove(relayers[i])) {
                emit RemoveWhitelistedRelayer(relayers[i]);
            }
        }
    }

    /// @inheritdoc IPriceRepository
    function getWhitelistedRelayers() external view virtual returns (address[] memory relayers) {
        relayers = PriceRepositoryStorage.layout().whitelistedRelayers.toArray();
    }

    /// @notice Revert if `account` is not an authorized relayer
    function _revertIfWhitelistedRelayerNotAuthorized(address account) internal view {
        if (PriceRepositoryStorage.layout().whitelistedRelayers.contains(account))
            revert PriceRepository__NotAuthorized(account);
    }
}
