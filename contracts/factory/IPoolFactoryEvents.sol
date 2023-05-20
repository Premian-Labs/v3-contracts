// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

interface IPoolFactoryEvents {
    event SetDiscountPerPool(UD60x18 indexed discountPerPool);
    event SetFeeReceiver(address indexed feeReceiver);
    event PoolDeployed(
        address indexed base,
        address indexed quote,
        address oracleAdapter,
        UD60x18 strike,
        uint256 maturity,
        bool isCallPool,
        address poolAddress
    );

    event PricingPath(
        address pool,
        address[][] basePath,
        uint8[] basePathDecimals,
        IOracleAdapter.AdapterType baseAdapterType,
        address[][] quotePath,
        uint8[] quotePathDecimals,
        IOracleAdapter.AdapterType quoteAdapterType
    );
}
