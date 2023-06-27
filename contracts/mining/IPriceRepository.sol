// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPriceRepository {
    error PriceRepository__NotAuthorized(address account);

    event AddRelayer(address indexed relayer);
    event RemoveRelayer(address indexed relayer);
    event PriceUpdate(address indexed base, address indexed quote, uint256 timestamp, UD60x18 price);

    /// @notice Returns the most recent price update, if zero, a price has not been recorded
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @return price for token pair (18 decimals)
    /// @return timestamp of most recent price update
    function getPrice(address base, address quote) external view returns (UD60x18, uint256);

    /// @notice Returns price at a given timestamp, if zero, a price has not been recorded
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @param timestamp Reference timestamp (in seconds)
    /// @return price for token pair (18 decimals)
    function getPriceAt(address base, address quote, uint256 timestamp) external view returns (UD60x18);

    /// @notice Add relayers to the whitelist so that they can add price updates
    /// @param accounts The addresses to add to the whitelist
    function addWhitelistedRelayers(address[] calldata accounts) external;

    /// @notice Remove relayers from the whitelist so that they cannot add priced updates
    /// @param accounts The addresses to remove from the whitelist
    function removeWhitelistedRelayers(address[] calldata accounts) external;

    /// @notice Get the list of whitelisted relayers
    /// @return The list of whitelisted relayers
    function getWhitelistedRelayers() external view returns (address[] memory);
}
