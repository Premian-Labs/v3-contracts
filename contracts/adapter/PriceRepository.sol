// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {RelayerAccessManager} from "../relayer/RelayerAccessManager.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

abstract contract PriceRepository is IPriceRepository, ReentrancyGuard, RelayerAccessManager {
    /// @inheritdoc IPriceRepository
    function setTokenPriceAt(address token, address denomination, uint256 timestamp, UD60x18 price) external virtual;

    /// @notice Returns the price of `token` denominated in `denomination` at a given timestamp, if zero, a price has
    ///         not been recorded
    function _getTokenPriceAt(
        address token,
        address denomination,
        uint256 timestamp
    ) internal view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().prices[token][denomination][timestamp];
    }
}
