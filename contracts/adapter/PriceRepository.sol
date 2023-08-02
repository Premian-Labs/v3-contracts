// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {RelayerAccessManager} from "../relayer/RelayerAccessManager.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepository is IPriceRepository, ReentrancyGuard, RelayerAccessManager {
    /// @inheritdoc IPriceRepository
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external virtual nonReentrant {
        _revertIfNotWhitelistedRelayer(msg.sender);
        PriceRepositoryStorage.layout().prices[base][quote][timestamp] = price;
        emit PriceUpdate(base, quote, timestamp, price);
    }

    /// @notice Returns the cached price at a given timestamp, if zero, a price has not been recorded
    function _getCachedPriceAt(address base, address quote, uint256 timestamp) internal view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().prices[base][quote][timestamp];
    }
}
