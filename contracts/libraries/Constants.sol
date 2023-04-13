// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

UD60x18 constant ZERO = UD60x18.wrap(0);
UD60x18 constant ONE_HALF = UD60x18.wrap(0.5e18);
UD60x18 constant ONE = UD60x18.wrap(1e18);
UD60x18 constant TWO = UD60x18.wrap(2e18);
UD60x18 constant THREE = UD60x18.wrap(3e18);
UD60x18 constant FIVE = UD60x18.wrap(5e18);
UD60x18 constant TEN = UD60x18.wrap(10e18);
UD60x18 constant ONE_THOUSAND = UD60x18.wrap(1000e18);

SD59x18 constant iZERO = SD59x18.wrap(0);
SD59x18 constant iONE_HALF = SD59x18.wrap(0.5e18);
SD59x18 constant iONE = SD59x18.wrap(1e18);
SD59x18 constant iTWO = SD59x18.wrap(2e18);
SD59x18 constant iFOUR = SD59x18.wrap(4e18);
SD59x18 constant iEIGHT = SD59x18.wrap(8e18);
SD59x18 constant iTEN = SD59x18.wrap(10e18);