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

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            address(0)
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy50Options_WithApproval() public {
        _test_trade_Buy50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_trade_Buy50Options_WithReferral(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        uint256 initialCollateral = deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

        uint256 totalRebate;

        {
            (
                UD60x18 primaryRebatePercent,
                UD60x18 secondaryRebatePercent
            ) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent *
                scaleDecimals(takerFee, isCall);

            UD60x18 _secondaryRebate = secondaryRebatePercent *
                scaleDecimals(takerFee, isCall);

            uint256 primaryRebate = scaleDecimals(_primaryRebate, isCall);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate, isCall);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken(isCall);

        vm.startPrank(users.trader);

        deal(token, users.trader, totalPremium);
        IERC20(token).approve(address(router), totalPremium);

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            users.referrer
        );

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), 0);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(
            IERC20(token).balanceOf(address(pool)),
            initialCollateral + totalPremium - totalRebate
        );
    }

    function test_trade_Buy50Options_WithReferral() public {
        _test_trade_Buy50Options_WithReferral(poolKey.isCallPool);
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

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            address(0)
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell50Options_WithApproval() public {
        _test_trade_Sell50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_trade_Sell50Options_WithReferral(bool isCall) internal {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        uint256 initialCollateral;

        {
            UD60x18 _collateral = contractsToCollateral(
                UD60x18.wrap(depositSize),
                isCall
            );

            initialCollateral = scaleDecimals(
                _collateral * posKey.lower.avg(posKey.upper),
                isCall
            );
        }

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        uint256 collateral = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        uint256 totalRebate;

        {
            (
                UD60x18 primaryRebatePercent,
                UD60x18 secondaryRebatePercent
            ) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent *
                scaleDecimals(takerFee, isCall);

            UD60x18 _secondaryRebate = secondaryRebatePercent *
                scaleDecimals(takerFee, isCall);

            uint256 primaryRebate = scaleDecimals(_primaryRebate, isCall);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate, isCall);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken(isCall);

        vm.startPrank(users.trader);

        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            users.referrer
        );

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), totalPremium);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(
            IERC20(token).balanceOf(address(pool)),
            initialCollateral + collateral - totalPremium - totalRebate
        );
    }

    function test_trade_Sell50Options_WithReferral() public {
        _test_trade_Sell50Options_WithReferral(poolKey.isCallPool);
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
        pool.trade(tradeSize, true, totalPremium - 1, address(0));
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
        pool.trade(tradeSize, false, totalPremium + 1, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit()
        public
    {
        _test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit(
            poolKey.isCallPool
        );
    }

    function test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity()
        public
    {
        posKey.orderType = Position.OrderType.CS;
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientAskLiquidity.selector);
        pool.trade(ud(depositSize + 1), true, 0, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity()
        public
    {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientBidLiquidity.selector);
        pool.trade(ud(depositSize + 1), false, 0, address(0));
    }

    function test_trade_RevertIf_TradeSizeIsZero() public {
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.trade(ud(0), true, 0, address(0));
    }

    function test_trade_RevertIf_Expired() public {
        vm.warp(poolKey.maturity);

        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.trade(ud(1), true, 0, address(0));
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
