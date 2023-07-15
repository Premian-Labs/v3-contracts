// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSafeTransferIgnoreDustTest is DeployTest {
    function test_exercise_TransferFullAmount() public {
        uint256 funds = isCallTest ? 5e17 : 500e6;
        deal(getPoolToken(), address(pool), funds);
        pool.mint(users.trader, 1, ud(1 ether));
        UD60x18 settlementPrice = isCallTest ? ud(2000 ether) : ud(500 ether);
        oracleAdapter.setPriceAt(settlementPrice);
        vm.warp(poolKey.maturity);
        vm.prank(users.trader);
        pool.exercise();
        uint256 balanceTrader = isCallTest ? 49700e13 : 49700e4;
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), balanceTrader);
    }

    function test_exercise_TransferLessThanFullAmount() public {
        uint256 funds = isCallTest ? 5e17 - 1e13 : 500e6 - 1e4;
        deal(getPoolToken(), address(pool), funds);
        pool.mint(users.trader, 1, ud(1 ether));
        UD60x18 settlementPrice = isCallTest ? ud(2000 ether) : ud(500 ether);
        oracleAdapter.setPriceAt(settlementPrice);
        vm.warp(poolKey.maturity);
        vm.prank(users.trader);
        pool.exercise();
        uint256 balanceTrader = isCallTest ? 49699e13 : 49699e4;
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), balanceTrader);
    }

    function test_safeTransferIgnoreDust_TransferFullAmount() public {
        uint256 funds = 52 ether;
        deal(getPoolToken(), address(pool), funds);
        vm.prank(users.trader);
        pool.safeTransferIgnoreDust(users.trader, 52 ether);
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), funds);
    }

    function test_safeTransferIgnoreDust_TransferLessThanFullAmount() public {
        uint256 funds = 52 ether;
        deal(getPoolToken(), address(pool), funds);
        vm.prank(users.trader);
        pool.safeTransferIgnoreDust(users.trader, funds + 1e15);
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), funds);
    }

    function test_safeTransferIgnoreDustUD60x18_TransferFullAmount() public {
        uint256 funds = isCallTest ? 52 ether : 52e6;
        deal(getPoolToken(), address(pool), funds);
        vm.prank(users.trader);
        pool.safeTransferIgnoreDustUD60x18(users.trader, ud(52 ether));
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), funds);
    }

    function test_safeTransferIgnoreDustUD60x18_TransferLessThanFullAmount() public {
        uint256 funds = isCallTest ? 52 ether : 52e6;
        uint256 diff = 1e15;
        deal(getPoolToken(), address(pool), funds);
        vm.prank(users.trader);
        pool.safeTransferIgnoreDustUD60x18(users.trader, ud(52 ether) + ud(diff));
        assertEq(IERC20(getPoolToken()).balanceOf(address(pool)), 0);
        assertEq(IERC20(getPoolToken()).balanceOf(users.trader), funds);
    }
}
