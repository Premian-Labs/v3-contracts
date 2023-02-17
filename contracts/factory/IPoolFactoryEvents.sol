// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IPoolFactoryEvents {
    event SetDiscountPerPool(uint256 indexed discountPerPool);
    event SetFeeReceiver(address indexed feeReceiver);
    event PoolDeployed(
        address indexed base,
        address indexed quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool,
        address poolAddress
    );
}
