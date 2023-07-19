// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {VolatilityOracleStorage} from "./VolatilityOracleStorage.sol";

interface IVolatilityOracle {
    error VolatilityOracle__ArrayLengthMismatch();
    error VolatilityOracle__OutOfBounds(int256 value);
    error VolatilityOracle__RelayerNotWhitelisted(address sender);
    error VolatilityOracle__SpotIsZero();
    error VolatilityOracle__StrikeIsZero();
    error VolatilityOracle__TimeToMaturityIsZero();

    event AddWhitelistedRelayer(address indexed account);
    event RemoveWhitelistedRelayer(address indexed account);
    event UpdateParameters(address indexed token, bytes32 tau, bytes32 theta, bytes32 psi, bytes32 rho);

    /// @notice Add relayers to the whitelist so that they can add oracle surfaces
    /// @param accounts The addresses to add to the whitelist
    function addWhitelistedRelayers(address[] calldata accounts) external;

    /// @notice Remove relayers from the whitelist so that they cannot add oracle surfaces
    /// @param accounts The addresses to remove from the whitelist
    function removeWhitelistedRelayers(address[] calldata accounts) external;

    /// @notice Get the list of whitelisted relayers
    /// @return The list of whitelisted relayers
    function getWhitelistedRelayers() external view returns (address[] memory);

    /// @notice Pack IV model parameters into a single bytes32
    /// @dev This function is used to pack the parameters into a single variable, which is then used as input in `update`
    /// @param params Parameters of IV model to pack
    /// @return result The packed parameters of IV model
    function formatParams(int256[5] calldata params) external pure returns (bytes32 result);

    /// @notice Unpack IV model parameters from a bytes32
    /// @param input Packed IV model parameters to unpack
    /// @return params The unpacked parameters of the IV model
    function parseParams(bytes32 input) external pure returns (int256[5] memory params);

    /// @notice Update a list of Anchored eSSVI model parameters
    /// @param tokens List of the base tokens
    /// @param tau List of maturities
    /// @param theta List of ATM total implied variance curves
    /// @param psi List of ATM skew curves
    /// @param rho List of rho curves
    /// @param riskFreeRate The risk-free rate
    function updateParams(
        address[] calldata tokens,
        bytes32[] calldata tau,
        bytes32[] calldata theta,
        bytes32[] calldata psi,
        bytes32[] calldata rho,
        UD60x18 riskFreeRate
    ) external;

    /// @notice Get the IV model parameters of a token pair
    /// @param token The token address
    /// @return The IV model parameters
    function getParams(address token) external view returns (VolatilityOracleStorage.Update memory);

    /// @notice Get unpacked IV model parameters
    /// @param token The token address
    /// @return The unpacked IV model parameters
    function getParamsUnpacked(address token) external view returns (VolatilityOracleStorage.Params memory);

    /// @notice Calculate the annualized volatility for given set of parameters
    /// @param token The token address
    /// @param spot The spot price of the token
    /// @param strike The strike price of the option
    /// @param timeToMaturity The time until maturity (denominated in years)
    /// @return The annualized implied volatility, where 1 is defined as 100%
    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 timeToMaturity
    ) external view returns (UD60x18);

    /// @notice Calculate the annualized volatility for given set of parameters
    /// @param token The token address
    /// @param spot The spot price of the token
    /// @param strike The strike price of the option
    /// @param timeToMaturity The time until maturity (denominated in years)
    /// @return The annualized implied volatility, where 1 is defined as 100%
    function getVolatility(
        address token,
        UD60x18 spot,
        UD60x18[] memory strike,
        UD60x18[] memory timeToMaturity
    ) external view returns (UD60x18[] memory);

    /// @notice Returns the current risk-free rate
    /// @return The current risk-free rate
    function getRiskFreeRate() external view returns (UD60x18);
}
