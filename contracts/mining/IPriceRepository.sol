// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPriceRepositoryEvents} from "./IPriceRepositoryEvents.sol";

interface IPriceRepository is IPriceRepositoryEvents {
    error PriceRepository__KeeperNotAuthorized(address sender, address keeper);
    error PriceRepository__NoPriceRecorded();

    /// @notice Returns the cached daily open spot price at a given timestamp. Note, prices are recorded daily at 8AM UTC
    /// @param base The exchange token (base token)
    /// @param quote The token to quote against (quote token)
    /// @param timestamp Reference timestamp (in seconds)
    /// @return Daily open price (18 decimals)
    function getDailyOpenPriceFrom(address base, address quote, uint256 timestamp) external view returns (UD60x18);
}
