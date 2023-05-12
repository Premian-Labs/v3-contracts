// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

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

        UD60x18 tradeSize = ud(500 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

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

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

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

    function _test_trade_RevertIf_BuyOptions_WithTotalPremiumAboveLimit(
        bool isCall
    ) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                totalPremium - 1,
                0,
                totalPremium
            )
        );
        pool.trade(tradeSize, true, totalPremium - 1);
    }

    function test_trade_RevertIf_BuyOptions_WithTotalPremiumAboveLimit()
        public
    {
        _test_trade_RevertIf_BuyOptions_WithTotalPremiumAboveLimit(
            poolKey.isCallPool
        );
    }

    function _test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit(
        bool isCall
    ) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                totalPremium + 1,
                totalPremium,
                type(uint256).max
            )
        );
        pool.trade(tradeSize, false, totalPremium + 1);
    }

    function test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit()
        public
    {
        _test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit(
            poolKey.isCallPool
        );
    }

    function _test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity(
        bool isCall
    ) internal {
        posKey.orderType = Position.OrderType.CS;
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientAskLiquidity.selector);
        pool.trade(ud(depositSize + 1), true, 0);
    }

    function test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity()
        public
    {
        _test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity(
            poolKey.isCallPool
        );
    }

    function _test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity(
        bool isCall
    ) internal {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientBidLiquidity.selector);
        pool.trade(ud(depositSize + 1), false, 0);
    }

    function test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity()
        public
    {
        _test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity(
            poolKey.isCallPool
        );
    }

    function _test_trade_RevertIf_TradeSizeIsZero(bool isCall) internal {
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.trade(ud(0), true, 0);
    }

    function test_trade_RevertIf_TradeSizeIsZero() public {
        _test_trade_RevertIf_TradeSizeIsZero(poolKey.isCallPool);
    }

    function _test_trade_RevertIf_Expired(bool isCall) internal {
        vm.warp(poolKey.maturity);

        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.trade(ud(1), true, 0);
    }

    function test_trade_RevertIf_Expired() public {
        _test_trade_RevertIf_Expired(poolKey.isCallPool);
    }

    function _test_annihilate_Success(bool isCall) internal {
        deposit(1000 ether);
        vm.startPrank(users.lp);

        address poolToken = getPoolToken(isCall);
        deal(
            poolToken,
            users.lp,
            scaleDecimals(contractsToCollateral(ud(1000 ether), isCall), isCall)
        );
        IERC20(poolToken).approve(address(router), type(uint256).max);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(ud(200 ether), isCall),
            isCall
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

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10);

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
