// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPriceRepository {
    event PriceUpdate(address indexed base, address indexed quote, uint256 timestamp, UD60x18 price);

    /// @notice Set the price of `base` in terms of `quote` at the given `timestamp`
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @param timestamp Reference timestamp (in seconds)
    /// @param price for token pair (18 decimals)
    function setPriceAt(address base, address quote, uint256 timestamp, UD60x18 price) external;
}
