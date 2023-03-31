// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTradeTest is DeployTest {
    function _test_trade_Buy50OptionsWithApproval(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 totalPremium = pool.getTradeQuote(tradeSize, true);

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy50OptionsWithApproval() public {
        _test_trade_Buy50OptionsWithApproval(poolKey.isCallPool);
    }

    function _test_trade_Sell50OptionsWithApproval(bool isCall) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        uint256 totalPremium = pool.getTradeQuote(tradeSize, false);

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell50OptionsWithApproval() public {
        _test_trade_Sell50OptionsWithApproval(poolKey.isCallPool);
    }
}
