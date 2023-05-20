// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolAnnihilateTest is DeployTest {
    function test_annihilate_Success() public {
        deposit(1000 ether);
        vm.startPrank(users.lp);

        address poolToken = getPoolToken();
        deal(
            poolToken,
            users.lp,
            scaleDecimals(contractsToCollateral(ud(1000 ether)))
        );
        IERC20(poolToken).approve(address(router), type(uint256).max);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(ud(200 ether))
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue,
            "1"
        );

        UD60x18 tradeSize = ud(1000 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            address(0)
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium,
            "poolToken lp 0"
        );

        vm.warp(block.timestamp + 60);
        UD60x18 withdrawSize = ud(300 ether);

        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(
            pool.balanceOf(users.lp, PoolStorage.SHORT),
            tradeSize,
            "lp short 1"
        );
        assertEq(
            pool.balanceOf(users.lp, PoolStorage.LONG),
            withdrawSize,
            "lp long 1"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.LONG),
            tradeSize - withdrawSize,
            "pool long 1"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium,
            "poolToken lp 1"
        );

        UD60x18 annihilateSize = ud(100 ether);
        pool.annihilate(annihilateSize);

        assertEq(
            pool.balanceOf(users.lp, PoolStorage.SHORT),
            tradeSize - annihilateSize,
            "lp short 2"
        );
        assertEq(
            pool.balanceOf(users.lp, PoolStorage.LONG),
            withdrawSize - annihilateSize,
            "lp long 2"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium + scaleDecimals(contractsToCollateral(annihilateSize)),
            "poolToken lp 2"
        );
    }
}
