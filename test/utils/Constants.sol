// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {UD50x28} from "contracts/libraries/UD50x28.sol";
import {SD49x28} from "contracts/libraries/SD49x28.sol";

abstract contract Constants {
    address internal constant FEE_RECEIVER = address(123456789);
    uint40 internal constant MAY_1_2023 = 1_682_899_200;
    uint40 internal constant MAX_UNIX_TIMESTAMP = 2_147_483_647; // 2^31 - 1

    /// @dev The maximum value an uint256 number can have.
    uint256 internal constant MAX_UINT256 = type(uint256).max;

    UD60x18 internal constant ZERO = UD60x18.wrap(0);
    UD60x18 internal constant ONE_HALF = UD60x18.wrap(0.5e18);
    UD60x18 internal constant ONE = UD60x18.wrap(1e18);
    UD60x18 internal constant TWO = UD60x18.wrap(2e18);
    UD60x18 internal constant THREE = UD60x18.wrap(3e18);
    UD60x18 internal constant FIVE = UD60x18.wrap(5e18);

    SD59x18 internal constant iZERO = SD59x18.wrap(0);
    SD59x18 internal constant iONE = SD59x18.wrap(1e18);
    SD59x18 internal constant iTWO = SD59x18.wrap(2e18);
    SD59x18 internal constant iFOUR = SD59x18.wrap(4e18);
    SD59x18 internal constant iNINE = SD59x18.wrap(9e18);

    UD50x28 internal constant UD50_ZERO = UD50x28.wrap(0);
    UD50x28 internal constant UD50_ONE = UD50x28.wrap(1e28);
    UD50x28 internal constant UD50_TWO = UD50x28.wrap(2e28);

    SD49x28 internal constant SD49_ZERO = SD49x28.wrap(0);
    SD49x28 internal constant SD49_ONE = SD49x28.wrap(1e28);
    SD49x28 internal constant SD49_TWO = SD49x28.wrap(2e28);

    uint256 internal constant WAD = 1e18;
    int256 internal constant iWAD = 1e18;
}
