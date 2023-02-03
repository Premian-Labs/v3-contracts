// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolFactory {
    error PoolFactory__ZeroAddress();
    error PoolFactory__IdenticalAddresses();
    error PoolFactory__InvalidMaturity();
    error PoolFactory__InvalidStrike();
    error PoolFactory__OptionExpired();
    error PoolFactory__OptionMaturityExceedsMax();
    error PoolFactory__OptionMaturityNot8UTC();
    error PoolFactory__OptionMaturityNotFriday();
    error PoolFactory__OptionMaturityNotLastFriday();
    error PoolFactory__OptionStrikeEqualsZero();
    error PoolFactory__OptionStrikeInvalid();
    error PoolFactory__PoolAlreadyDeployed();

    event PoolDeployed(
        address indexed base,
        address indexed quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        address poolAddress
    );

    /// @notice Returns whether a pool has been deployed with those parameters or not
    /// @param base Address of base token
    /// @param quote Address of quote token
    /// @param baseOracle Address of base token price feed
    /// @param quoteOracle Address of quote token price feed
    /// @param strike The strike of the option
    /// @param maturity The maturity timestamp of the option
    /// @param isCallPool Whether the pool is for call or put options
    /// @return Whether a pool has already been deployed with those parameters or not
    function isPoolDeployed(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool);

    /// @notice Deploy a new option pool
    /// @param base Address of base token
    /// @param quote Address of quote token
    /// @param baseOracle Address of base token price feed
    /// @param quoteOracle Address of quote token price feed
    /// @param strike The strike of the option
    /// @param maturity The maturity timestamp of the option
    /// @param isCallPool Whether the pool is for call or put options
    /// @return poolAddress The address of the deployed pool
    function deployPool(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external returns (address poolAddress);
}
