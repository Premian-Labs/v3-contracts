// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";

library PRBMathExtended {
    function wr(uint256 x) internal pure returns (UD60x18) {
        return UD60x18.wrap(x);
    }

    function wr(int256 x) internal pure returns (SD59x18) {
        return SD59x18.wrap(x);
    }

    function uw(UD60x18 x) internal pure returns (uint256) {
        return UD60x18.unwrap(x);
    }

    function uw(SD59x18 x) internal pure returns (int256) {
        return SD59x18.unwrap(x);
    }
}
