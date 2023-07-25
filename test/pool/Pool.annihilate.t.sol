// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolAnnihilateTest is DeployTest {
    UD60x18 internal withdrawSize = UD60x18.wrap(300 ether);
    UD60x18 internal annihilateSize = UD60x18.wrap(100 ether);
    UD60x18 internal tradeSize = UD60x18.wrap(1000 ether);

    function init() internal returns (uint256 totalPremium) {
        deposit(1000 ether);
        vm.startPrank(users.lp);

        address poolToken = getPoolToken();
        deal(poolToken, users.lp, toTokenDecimals(contractsToCollateral(ud(1000 ether))));
        IERC20(poolToken).approve(address(router), type(uint256).max);

        uint256 depositCollateralValue = toTokenDecimals(contractsToCollateral(ud(200 ether)));

        assertEq(IERC20(poolToken).balanceOf(address(pool)), depositCollateralValue, "1");

        (totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, address(0));

        assertEq(IERC20(poolToken).balanceOf(users.lp), totalPremium, "poolToken lp 0");

        vm.warp(block.timestamp + 60);

        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), tradeSize, "lp short 1");
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), withdrawSize, "lp long 1");
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize - withdrawSize, "pool long 1");
        assertEq(IERC20(poolToken).balanceOf(users.lp), totalPremium, "poolToken lp 1");
        vm.stopPrank();
    }

    function test_annihilate_Success() public {
        uint256 totalPremium = init();
        address poolToken = getPoolToken();

        vm.prank(users.lp);
        pool.annihilate(annihilateSize);

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), tradeSize - annihilateSize, "lp short 2");
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), withdrawSize - annihilateSize, "lp long 2");
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium + toTokenDecimals(contractsToCollateral(annihilateSize)),
            "poolToken lp 2"
        );
    }

    function test_annihilateFor_Success() public {
        uint256 totalPremium = init();
        address poolToken = getPoolToken();

        setActionAuthorization(users.lp, IUserSettings.Action.Annihilate, true);

        vm.prank(users.operator);
        pool.annihilateFor(users.lp, annihilateSize);

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), tradeSize - annihilateSize, "lp short 2");
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), withdrawSize - annihilateSize, "lp long 2");
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium + toTokenDecimals(contractsToCollateral(annihilateSize)),
            "poolToken lp 2"
        );
    }

    function test_annihilateFor_RevertIf_ActionNotAuthorized() public {
        init();

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__ActionNotAuthorized.selector,
                users.lp,
                users.operator,
                IUserSettings.Action.Annihilate
            )
        );

        vm.prank(users.operator);
        pool.annihilateFor(users.lp, annihilateSize);
    }
}
