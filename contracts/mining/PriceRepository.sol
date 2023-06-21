// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ZERO} from "../libraries/Constants.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepository is IPriceRepository, OwnableInternal {
    /// @notice Set the address of the `keeper`
    function setKeeper(address keeper) external onlyOwner {
        PriceRepositoryStorage.layout().keeper = keeper;
        emit SetKeeper(keeper);
    }

    /// @notice Set the price of `base` in terms of `quote` at the given `timestamp`
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();
        if (msg.sender != l.keeper) revert PriceRepository__KeeperNotAuthorized(l.keeper);
        l.latestPrice[base][quote] = price;
        l.prices[base][quote][timestamp] = price;
        emit SetDailyOpenPrice(base, quote, timestamp, price);
    }

    /// @inheritdoc IPriceRepository
    function getPrice(address base, address quote) external view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().latestPrice[base][quote];
    }

    /// @inheritdoc IPriceRepository
    function getPriceAt(address base, address quote, uint256 timestamp) external view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().prices[base][quote][timestamp];
    }
}
