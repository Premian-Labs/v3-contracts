// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {IPoolFactoryEvents} from "./IPoolFactoryEvents.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

contract PoolFactoryProxy is IPoolFactoryEvents, ProxyUpgradeableOwnable {
    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {}
}
