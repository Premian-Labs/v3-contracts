// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolFactoryEvents} from "./IPoolFactoryEvents.sol";

interface IPoolFactory is IPoolFactoryEvents {
    error PoolFactory__ZeroAddress();
    error PoolFactory__IdenticalAddresses();
    error PoolFactory__InitializationFeeRequired();
    error PoolFactory__InvalidMaturity();
    error PoolFactory__InvalidStrike();
    error PoolFactory__NegativeSpotPrice();
    error PoolFactory__NotAuthorized();
    error PoolFactory__OptionExpired();
    error PoolFactory__OptionMaturityExceedsMax();
    error PoolFactory__OptionMaturityNot8UTC();
    error PoolFactory__OptionMaturityNotFriday();
    error PoolFactory__OptionMaturityNotLastFriday();
    error PoolFactory__OptionStrikeEqualsZero();
    error PoolFactory__OptionStrikeInvalid();
    error PoolFactory__PoolAlreadyDeployed();
    error PoolFactory__PoolNotExpired();

    struct PoolKey {
        // Address of base token
        address base;
        // Address of quote token
        address quote;
        // Address of base token price feed
        address baseOracle;
        // Address of quote token price feed
        address quoteOracle;
        // The strike of the option
        uint256 strike;
        // The maturity timestamp of the option
        uint64 maturity;
        // Whether the pool is for call or put options
        bool isCallPool;
    }

    /// @notice Returns whether a pool has been deployed with those parameters or not
    /// @param k The pool key
    /// @return Whether a pool has already been deployed with those parameters or not
    function isPoolDeployed(PoolKey memory k) external view returns (bool);

    /// @notice Returns the fee required to initialize a pool
    /// @param k The pool key
    /// @return The fee required to initialize this pool
    function initializationFee(
        PoolKey memory k
    ) external view returns (uint256);

    /// @notice Set the discountPerPool for new pools - only callable by owner
    /// @param discountPerPool The new discount percentage denominated in 1e18
    function setDiscountPerPool(uint256 discountPerPool) external;

    /// @notice Set the feeReceiver for initialization fees - only callable by owner
    /// @param feeReceiver The new fee receiver address
    function setFeeReceiver(address feeReceiver) external;

    /// @notice Deploy a new option pool
    /// @param k The pool key
    /// @return poolAddress The address of the deployed pool
    function deployPool(
        PoolKey memory k
    ) external payable returns (address poolAddress);

    /// @notice Removes the discount caused by an existing pool,
    ///         can only be called by the pool after maturity
    /// @param k The pool key
    function removeDiscount(PoolKey memory k) external;
}
