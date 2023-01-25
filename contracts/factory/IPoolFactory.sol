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
        address indexed underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        address poolAddress
    );

    function getDeploymentAddress(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (address);

    function isPoolDeployed(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool);

    function deployPool(
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external returns (address poolAddress);
}
