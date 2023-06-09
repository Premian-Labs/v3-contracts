// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPriceRepositoryEvents {
    event SetKeeper(address indexed keeper);
    event SetDailyOpenPrice(address indexed base, address indexed quote, uint256 timestamp, UD60x18 price);
}
