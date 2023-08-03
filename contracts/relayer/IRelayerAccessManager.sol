// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IRelayerAccessManager {
    error RelayerAccessManager__NotWhitelistedRelayer(address relayer);

    event AddWhitelistedRelayer(address indexed relayer);
    event RemoveWhitelistedRelayer(address indexed relayer);

    /// @notice Add relayers to the whitelist so that they can add price updates
    /// @param relayers The addresses to add to the whitelist
    function addWhitelistedRelayers(address[] calldata relayers) external;

    /// @notice Remove relayers from the whitelist so that they cannot add priced updates
    /// @param relayers The addresses to remove from the whitelist
    function removeWhitelistedRelayers(address[] calldata relayers) external;

    /// @notice Get the list of whitelisted relayers
    /// @return relayers The list of whitelisted relayers
    function getWhitelistedRelayers() external view returns (address[] memory relayers);
}
