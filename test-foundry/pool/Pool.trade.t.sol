// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTradeTest is DeployTest {
    function _test_trade_Buy50Options_WithApproval(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, true);

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(tradeSize, true, totalPremium + totalPremium / 10);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy50Options_WithApproval() public {
        _test_trade_Buy50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_trade_Sell50Options_WithApproval(bool isCall) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, false);

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell50Options_WithApproval() public {
        _test_trade_Sell50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_annihilate_Success(bool isCall) internal {
        deposit(1000 ether);
        vm.startPrank(users.lp);

        address poolToken = getPoolToken(isCall);
        deal(
            poolToken,
            users.lp,
            scaleDecimals(
                contractsToCollateral(UD60x18.wrap(1000 ether), isCall),
                isCall
            )
        );
        IERC20(poolToken).approve(address(router), type(uint256).max);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(200 ether), isCall),
            isCall
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue,
            "1"
        );

        UD60x18 tradeSize = UD60x18.wrap(1000 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, false);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10);

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium,
            "poolToken lp 0"
        );

        vm.warp(block.timestamp + 60);
        UD60x18 withdrawSize = UD60x18.wrap(300 ether);

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

        UD60x18 annihilateSize = UD60x18.wrap(100 ether);
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
            totalPremium +
                scaleDecimals(
                    contractsToCollateral(annihilateSize, isCall),
                    isCall
                ),
            "poolToken lp 2"
        );
    }

    function test_annihilate_Success() public {
        _test_annihilate_Success(poolKey.isCallPool);
    }
}
