// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPriceRepositoryEvents} from "./IPriceRepositoryEvents.sol";

interface IPriceRepository is IPriceRepositoryEvents {
    error PriceRepository__KeeperNotAuthorized(address keeper);

    /// @notice Returns the most recent cached price, if zero, a price has not been recorded
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @return price for token pair (18 decimals)
    function getPrice(address base, address quote) external view returns (UD60x18);

    /// @notice Returns the cached price at a given timestamp, if zero, a price has not been recorded
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @param timestamp Reference timestamp (in seconds)
    /// @return price for token pair (18 decimals)
    function getPriceAt(address base, address quote, uint256 timestamp) external view returns (UD60x18);
}
