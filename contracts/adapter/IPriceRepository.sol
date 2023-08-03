// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPriceRepository {
    error PriceRepository__NotAuthorized(address account);

    event AddWhitelistedRelayer(address indexed account);
    event RemoveWhitelistedRelayer(address indexed account);
    event PriceUpdate(address indexed base, address indexed quote, uint256 timestamp, UD60x18 price);

    /// @notice Set the price of `base` in terms of `quote` at the given `timestamp`
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @param timestamp Reference timestamp (in seconds)
    /// @param price for token pair (18 decimals)
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external;

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
