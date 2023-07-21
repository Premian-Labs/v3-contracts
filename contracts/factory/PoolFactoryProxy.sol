// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {IPoolFactoryEvents} from "./IPoolFactoryEvents.sol";

import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";
import {ZERO, ONE} from "../libraries/Constants.sol";

contract PoolFactoryProxy is IPoolFactoryEvents, ProxyUpgradeableOwnable {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;

    constructor(
        address implementation,
        UD60x18 discountPerPool,
        address feeReceiver
    ) ProxyUpgradeableOwnable(implementation) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        if (discountPerPool == ZERO || discountPerPool >= ONE) revert IPoolFactory.PoolFactory__InvalidInput();
        l.discountPerPool = discountPerPool;
        emit SetDiscountPerPool(discountPerPool);

        l.feeReceiver = feeReceiver;
        emit SetFeeReceiver(feeReceiver);
    }
}
