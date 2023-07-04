// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {ZERO} from "../libraries/Constants.sol";

import {IPriceRepository} from "./IPriceRepository.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepository is IPriceRepository, OwnableInternal {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Set the price of `base` in terms of `quote` at the given `timestamp`
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();
        if (!l.whitelistedRelayers.contains(msg.sender)) revert PriceRepository__NotAuthorized(msg.sender);
        l.latestPriceTimestamp[base][quote] = timestamp;
        l.prices[base][quote][timestamp] = price;
        emit PriceUpdate(base, quote, timestamp, price);
    }

    /// @inheritdoc IPriceRepository
    function getPrice(address base, address quote) external view returns (UD60x18 price, uint256 timestamp) {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();
        timestamp = l.latestPriceTimestamp[base][quote];
        price = l.prices[base][quote][timestamp];
    }

    /// @inheritdoc IPriceRepository
    function getPriceAt(address base, address quote, uint256 timestamp) external view returns (UD60x18 price) {
        price = PriceRepositoryStorage.layout().prices[base][quote][timestamp];
    }

    /// @inheritdoc IPriceRepository
    function addWhitelistedRelayers(address[] calldata accounts) external onlyOwner {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            if (l.whitelistedRelayers.add(accounts[i])) {
                emit AddRelayer(accounts[i]);
            }
        }
    }

    /// @inheritdoc IPriceRepository
    function removeWhitelistedRelayers(address[] calldata accounts) external onlyOwner {
        PriceRepositoryStorage.Layout storage l = PriceRepositoryStorage.layout();

        for (uint256 i = 0; i < accounts.length; i++) {
            if (l.whitelistedRelayers.remove(accounts[i])) {
                emit RemoveRelayer(accounts[i]);
            }
        }
    }

    /// @inheritdoc IPriceRepository
    function getWhitelistedRelayers() external view returns (address[] memory) {
        return PriceRepositoryStorage.layout().whitelistedRelayers.toArray();
    }
}
