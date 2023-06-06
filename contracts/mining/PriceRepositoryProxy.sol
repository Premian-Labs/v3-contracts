// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

import {IPriceRepositoryEvents} from "./IPriceRepositoryEvents.sol";
import {PriceRepositoryStorage} from "./PriceRepositoryStorage.sol";

contract PriceRepositoryProxy is IPriceRepositoryEvents, ProxyUpgradeableOwnable {
    constructor(address implementation, address keeper) ProxyUpgradeableOwnable(implementation) {
        PriceRepositoryStorage.layout().keeper = keeper;
        emit SetKeeper(keeper);
    }
}
