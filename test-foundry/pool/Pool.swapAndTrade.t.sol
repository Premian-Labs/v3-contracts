// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSwapAndTradeTest is DeployTest {
    function _test_swapAndTrade_Buy50Options(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 totalPremium = pool.getTradeQuote(tradeSize, true);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);

        uint256 swapQuote = getSwapQuote(swapToken, poolToken, totalPremium);
        deal(swapToken, users.trader, swapQuote);
        IERC20(swapToken).approve(address(router), type(uint256).max);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgs(
            swapToken,
            poolToken,
            swapQuote,
            totalPremium,
            users.trader
        );

        pool.swapAndTrade(
            swapArgs,
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_swapAndTrade_Buy50Options() public {
        _test_swapAndTrade_Buy50Options(poolKey.isCallPool);
    }

    function _test_swapAndTrade_Sell50Options(bool isCall) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        uint256 totalPremium = pool.getTradeQuote(tradeSize, false);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);

        uint256 swapQuote = getSwapQuote(
            swapToken,
            poolToken,
            collateralScaled
        );
        deal(swapToken, users.trader, swapQuote);
        IERC20(swapToken).approve(address(router), type(uint256).max);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgs(
            swapToken,
            poolToken,
            swapQuote,
            collateralScaled,
            users.trader
        );

        pool.swapAndTrade(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_swapAndTrade_Sell50Options() public {
        _test_swapAndTrade_Sell50Options(poolKey.isCallPool);
    }
}
