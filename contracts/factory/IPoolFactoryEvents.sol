// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracleAdapter} from "../oracle/price/IOracleAdapter.sol";

import {IPoolFactory} from "./IPoolFactory.sol";

interface IPoolFactoryEvents {
    event SetDiscountPerPool(uint256 indexed discountPerPool);
    event SetFeeReceiver(address indexed feeReceiver);
    event PoolDeployed(
        address indexed base,
        address indexed quote,
        address oracleAdapter,
        uint256 strike,
        uint64 maturity,
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
