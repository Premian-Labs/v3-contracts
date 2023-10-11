// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PRBMathExtra} from "contracts/libraries/PRBMathExtra.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

abstract contract PoolStorageTest is DeployTest {
    UD60x18 valueUD = ud(3 ether);
    SD59x18 valueSD = sd(3 ether);
    UD60x18 valueExtendedUD = ud(3 ether) + ud(1);
    SD59x18 valueExtendedSD = sd(3 ether) + sd(1);
    SD59x18 valueSDNeg = sd(-3 ether);
    SD59x18 valueExtendedSDNeg = sd(-3 ether) + sd(1);

    function test_roundDown() public {
        assertEq(pool.exposed_roundDown(valueUD), isCallTest ? 3 ether : 3e6);
        assertEq(pool.exposed_roundDown(valueExtendedUD), isCallTest ? 3 ether : 3e6);
    }

    function test_roundDownUD60x18() public {
        assertEq(pool.exposed_roundDownUD60x18(valueUD), valueUD);
        assertEq(pool.exposed_roundDownUD60x18(valueExtendedUD), isCallTest ? valueUD : valueUD + ud(3e12));
    }

    function test_roundDownSD59x18() public {
        assertEq(pool.exposed_roundDownSD59x18(valueSD), valueSD);
        assertEq(pool.exposed_roundDownSD59x18(valueExtendedSD), valueSD);
        assertEq(pool.exposed_roundDownSD59x18(valueExtendedSDNeg), valueSDNeg);
    }

    function test_roundUp() public {
        assertEq(pool.exposed_roundUp(valueUD), isCallTest ? 3 ether : 3e6);
        assertEq(pool.exposed_roundUp(valueExtendedUD), isCallTest ? (3 ether + 1) : 3e6 + 1);
    }

    function test_roundUpUD60x18() public {
        assertEq(pool.exposed_roundUpUD60x18(valueUD), valueUD);
        assertEq(pool.exposed_roundUpUD60x18(valueExtendedUD), isCallTest ? valueExtendedUD : ud(3 ether) + ud(3e12));
    }
}
