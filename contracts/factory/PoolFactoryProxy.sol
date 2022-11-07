// SPDX-License-Identifier: UNLICENSED

// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

contract PoolFactoryProxy is ProxyUpgradeableOwnable {
    constructor(address implementation)
        ProxyUpgradeableOwnable(implementation)
    {}
}
