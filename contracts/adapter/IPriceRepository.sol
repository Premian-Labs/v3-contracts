// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPriceRepository {
    event PriceUpdate(address indexed token, address indexed denomination, uint256 timestamp, UD60x18 price);

    /// @notice Set the price of `token` denominated in `denomination` at the given `timestamp`
    /// @param token The exchange token (ERC20 token)
    /// @param denomination The Chainlink token denomination to quote against (ETH, BTC, or USD)
    /// @param timestamp Reference timestamp (in seconds)
    /// @param price The amount of `token` denominated in `denomination` (18 decimals)
    function setTokenPriceAt(address token, address denomination, uint256 timestamp, UD60x18 price) external;
}
