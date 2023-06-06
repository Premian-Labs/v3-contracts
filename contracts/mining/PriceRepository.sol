// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ZERO} from "../libraries/Constants.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepository is IPriceRepository, OwnableInternal {
    using PriceRepositoryStorage for PriceRepositoryStorage.Layout;

    function setKeeper(address keeper) external onlyOwner {
        PriceRepositoryStorage.layout().keeper = keeper;
        emit SetKeeper(keeper);
    }

    function setDailyOpenPrice(address base, address quote, uint256 timestamp, UD60x18 price) external {
        address keeper = PriceRepositoryStorage.layout().keeper;
        if (msg.sender != keeper) revert PriceRepository__KeeperNotAuthorized(msg.sender, keeper);
        PriceRepositoryStorage.layout().dailyOpenPrice[base][quote][timestamp] = price;
        emit SetDailyOpenPrice(msg.sender, base, quote, timestamp, price);
    }

    function getDailyOpenPriceFrom(
        address base,
        address quote,
        uint256 timestamp
    ) external view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().dailyOpenPrice[base][quote][timestamp];
        if (price == ZERO) revert PriceRepository__NoPriceRecorded();
    }
}
