// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

interface IPosition {
    error Position__InvalidOrderType();
    error Position__InvalidPositionUpdate(
        UD60x18 currentBalance,
        SD59x18 amount
    );
    error Position__LowerGreaterOrEqualUpper(UD60x18 lower, UD60x18 upper);
}
