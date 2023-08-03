// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {PriceRepository} from "../../adapter/PriceRepository.sol";

contract PriceRepositoryMock is PriceRepository {
    function __getCachedPriceAt(address base, address quote, uint256 timestamp) external view returns (UD60x18 price) {
        return _getCachedPriceAt(base, quote, timestamp);
    }
}
