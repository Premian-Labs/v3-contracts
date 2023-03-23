// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

interface IPoolFactoryEvents {
    event SetDiscountPerPool(UD60x18 indexed discountPerPool);
    event SetFeeReceiver(address indexed feeReceiver);
    event PoolDeployed(
        address indexed base,
        address indexed quote,
        address oracleAdapter,
        UD60x18 strike,
        uint64 maturity,
        bool isCallPool,
        address poolAddress
    );
}
