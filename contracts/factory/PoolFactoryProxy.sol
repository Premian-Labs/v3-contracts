// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

contract PoolFactoryProxy is ProxyUpgradeableOwnable {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    
    constructor(address implementation, uint256 discountPerPool, address feeReceiver)
        ProxyUpgradeableOwnable(implementation)
    {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        l.discountPerPool = discountPerPool;
        l.feeReceiver = feeReceiver;
    }
}
