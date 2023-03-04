// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {VolatilityOracleStorage} from "./VolatilityOracleStorage.sol";

interface IVolatilityOracle {
    error VolatilityOracle__ArrayLengthMismatch();
    error VolatilityOracle__RelayerNotWhitelisted();
    error VolatilityOracle__SpotIsZero();
    error VolatilityOracle__StrikeIsZero();
    error VolatilityOracle__TimeToMaturityIsZero();

    /// @notice Add relayers to the whitelist so that they can add oracle surfaces
    /// @param accounts The addresses to add to the whitelist
    function addWhitelistedRelayers(address[] memory accounts) external;

    /// @notice Remove relayers from the whitelist so that they cannot add oracle surfaces
    /// @param accounts The addresses to remove from the whitelist
    function removeWhitelistedRelayers(address[] memory accounts) external;

    /// @notice Get the list of whitelisted relayers
    /// @return The list of whitelisted relayers
    function getWhitelistedRelayers() external view returns (address[] memory);

    /// @notice Pack IV model parameters into a single bytes32
    /// @dev This function is used to pack the parameters into a single variable, which is then used as input in `update`
    /// @param params Parameters of IV model to pack
    /// @return result The packed parameters of IV model
    function formatParams(
        int256[5] memory params
    ) external pure returns (bytes32 result);

    /// @notice Unpack IV model parameters from a bytes32
    /// @param input Packed IV model parameters to unpack
    /// @return params The unpacked parameters of the IV model
    function parseParams(
        bytes32 input
    ) external pure returns (int256[] memory params);

    /// @notice Update a list of Anchored eSSVI model parameters
    /// @param tokens List of the base tokens
    /// @param tau List of maturities
    /// @param theta List of ATM total implied variance curves
    /// @param psi List of ATM skew curves
    /// @param rho List of rho curves
    function updateParams(
        address[] memory tokens,
        bytes32[] memory tau,
        bytes32[] memory theta,
        bytes32[] memory psi,
        bytes32[] memory rho
    ) external;

    /// @notice Get the IV model parameters of a token pair
    /// @param token The token address
    /// @return The IV model parameters
    function getParams(
        address token
    ) external view returns (VolatilityOracleStorage.Update memory);

    /// @notice Get unpacked IV model parameters
    /// @param token The token address
    /// @return The unpacked IV model parameters
    function getParamsUnpacked(
        address token
    ) external view returns (VolatilityOracleStorage.Params memory);

    /// @notice Calculate the annualized volatility for given set of parameters
    /// @param token The token address
    /// @param spot The spot price of the token
    /// @param strike The strike price of the option
    /// @param timeToMaturity The time until maturity (denominated in years)
    /// @return The annualized implied volatility, where 1 is defined as 100%
    function getVolatility(
        address token,
        uint256 spot,
        uint256 strike,
        uint256 timeToMaturity
    ) external view returns (uint256);

    /// @notice Calculate the annualized volatility for given set of parameters
    /// @param token The token address
    /// @param spot The spot price of the token
    /// @param strike The strike price of the option
    /// @param timeToMaturity The time until maturity (denominated in years)
    /// @return The annualized implied volatility, where 1 is defined as 100%
    function getVolatility(
        address token,
        uint256 spot,
        uint256[] memory strike,
        uint256[] memory timeToMaturity
    ) external view returns (uint256[] memory);

    function getrfRate() external pure returns (uint256);
}
