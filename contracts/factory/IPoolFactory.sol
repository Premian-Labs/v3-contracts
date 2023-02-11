// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IPoolFactory {
    error PoolFactory__ZeroAddress();
    error PoolFactory__IdenticalAddresses();
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

    event SetDiscountBps(uint256 indexed discountPerPool);
    event SetDiscountAdmin(address indexed discountAdmin);
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

    /// @notice Returns the fee required to initialize a pool
    /// @param base Address of base token
    /// @param quote Address of quote token
    /// @param baseOracle Address of base token price feed
    /// @param quoteOracle Address of quote token price feed
    /// @param strike The strike of the option
    /// @param maturity The maturity timestamp of the option
    /// @param isCallPool Whether the pool is for call or put options
    /// @return The fee required to initialize this pool
    function initializationFee(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
     ) external view returns (uint256);
    
    /// @notice Set the discountPerPool for new pools - only callable by discountAdmin
    /// @param discountPerPool The new discount percentage denominated in 1e18
    function setDiscountBps(uint256 discountPerPool) external;
    
    /// @notice Set the new discountAdmin - only callable by discountAdmin
    /// @param discountAdmin The new discount admin address
    function setDiscountAdmin(address discountAdmin) external;
    
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
    
    /// @notice Removes an existing pool, can only be called by the pool after maturity
    /// @param base Address of base token
    /// @param quote Address of quote token
    /// @param baseOracle Address of base token price feed
    /// @param quoteOracle Address of quote token price feed
    /// @param strike The strike of the option
    /// @param maturity The maturity timestamp of the option
    /// @param isCallPool Whether the pool is for call or put options
    function removePool(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external;
}
