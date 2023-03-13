// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IPoolFactoryEvents} from "./IPoolFactoryEvents.sol";

import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

contract PoolFactoryProxy is IPoolFactoryEvents, ProxyUpgradeableOwnable {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    constructor(
        address implementation,
        UD60x18 discountPerPool,
        address feeReceiver
    ) ProxyUpgradeableOwnable(implementation) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        l.discountPerPool = discountPerPool;
        emit SetDiscountPerPool(discountPerPool);

        l.feeReceiver = feeReceiver;
        emit SetFeeReceiver(feeReceiver);
    }
}
