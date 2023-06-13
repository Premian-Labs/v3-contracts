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
    function test_trade_Buy500Options_WithApproval() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, true);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);

        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(tradeSize, true, totalPremium + totalPremium / 10, address(0));

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy500Options_WithReferral() public {
        posKey.orderType = Position.OrderType.CS;
        uint256 initialCollateral = deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(users.trader, tradeSize, true);

        uint256 totalRebate;

        {
            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(takerFee);

            UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(takerFee);

            uint256 primaryRebate = scaleDecimals(_primaryRebate);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken();

        vm.startPrank(users.trader);

        deal(token, users.trader, totalPremium);
        IERC20(token).approve(address(router), totalPremium);

        pool.trade(tradeSize, true, totalPremium + totalPremium / 10, users.referrer);

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), 0);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(IERC20(token).balanceOf(address(pool)), initialCollateral + totalPremium - totalRebate);
    }

    function test_trade_Buy50Options_HandleRoundingErrors_WithReferral() public {
        // Rounding errors were discovered in Call Pool, the following tx's replicate the pool state
        if (!poolKey.isCallPool) return;

        vm.startPrank(users.lp);
        address token = getPoolToken();

        // Network: Arbitrum Goerli
        // 0x1cfa9ec7273123bf58b64409223ab444be31a8528a4a2e7e54aeff5c15596d25
        posKey.orderType = Position.OrderType.LC;
        posKey.lower = ud(1000000000000000);
        posKey.upper = ud(134000000000000000);
        UD60x18 nearestBelowLower = ud(1000000000000000);
        UD60x18 nearestBelowUpper = ud(1000000000000000);
        UD60x18 depositSize = ud(5000000000000000000);
        UD60x18 minMarketPrice = ZERO;
        UD60x18 maxMarketPrice = ud(1000000000000000000);

        uint256 initialCollateral = scaleDecimals(poolKey.isCallPool ? depositSize : depositSize * poolKey.strike);
        deal(token, users.lp, initialCollateral);
        IERC20(token).approve(address(router), initialCollateral);
        pool.deposit(posKey, nearestBelowLower, nearestBelowUpper, depositSize, minMarketPrice, maxMarketPrice);

        // 0x2d33b0c49c8dd3ab75b48e0c33b040eb447ff373aac9ebcfdec2c4ffb74f7c2e
        posKey.orderType = Position.OrderType.CS;
        posKey.lower = ud(134000000000000000);
        posKey.upper = ud(319000000000000000);
        nearestBelowLower = ud(134000000000000000);
        nearestBelowUpper = ud(134000000000000000);
        depositSize = ud(5000000000000000000);
        minMarketPrice = ud(0);
        maxMarketPrice = ud(1000000000000000000);

        initialCollateral = scaleDecimals(poolKey.isCallPool ? depositSize : depositSize * poolKey.strike);
        deal(token, users.lp, initialCollateral);
        IERC20(token).approve(address(router), initialCollateral);
        pool.deposit(posKey, nearestBelowLower, nearestBelowUpper, depositSize, minMarketPrice, maxMarketPrice);
        vm.stopPrank();

        vm.startPrank(users.trader);
        UD60x18 size = ud(1000000000000000000);
        uint256 collateral = scaleDecimals(contractsToCollateral(size));
        uint256 premiumLimit = scaleDecimals(ud(113458000000000000));
        // 0x43c6b90d645c0ffcaeb1bbf454a5f3631bd200249f4bc613f4606e68126e8f74
        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);
        pool.trade(size, false, premiumLimit, users.referrer);

        size = ud(500000000000000000);
        premiumLimit = scaleDecimals(ud(60446500000000000));
        // 0xc884a63f3ba0f81a70679064df644d0bb980ea532c8e326068b403f03ea357dc
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        size = ud(400000000000000000);
        premiumLimit = scaleDecimals(ud(53432480000000000));
        // 0x70fa20d6f011e8fbc660f52405249579623cf1d2b416d3836a2a2bc7f27523db
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        size = ud(100000000000000000);
        premiumLimit = scaleDecimals(ud(14063019999999997));
        // 0xccb5328d0675d73690ee9f865b4752b9c2f411887e87766fda69e14ac7a793bf
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        size = ud(500000000000000000);
        premiumLimit = scaleDecimals(ud(78922499999999995));
        // 0x27e11404ee3461fa83abfca06a7857659464156f487e3965c91daf31bf1d8b16
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        size = ud(500000000000000000);
        collateral = scaleDecimals(contractsToCollateral(size));
        premiumLimit = scaleDecimals(ud(67327499999999999));
        // 0xf44cb672b1cdd743a64564d8a986204eaf0b3ce0ced01d618106206757697dd1
        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);
        pool.trade(size, false, premiumLimit, users.referrer);

        size = ud(499999900000000000);
        collateral = scaleDecimals(contractsToCollateral(size));
        premiumLimit = scaleDecimals(ud(59854488654199876));
        // 0xa93cfd0aa129e5957e27a09b067449828583865ffac1445fa1d6963896773eaa
        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);
        pool.trade(size, false, premiumLimit, users.referrer);

        size = ud(400000000000000000);
        premiumLimit = scaleDecimals(ud(53432481127839997));
        // 0x01149a9092242f1867242719e13cf0e8f9b027d0b360c181d040fce98c376788
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        size = ud(400000000000000000);
        collateral = scaleDecimals(contractsToCollateral(size));
        premiumLimit = scaleDecimals(ud(47383521000160001));
        // 0xa9cb628d70239dfca9c5e7178b902ff26a55e9808f8e0263905afec297400ff7
        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);
        pool.trade(size, false, premiumLimit, users.referrer);

        size = ud(490000000000000000);
        premiumLimit = scaleDecimals(ud(66076511181603997));
        // 0xb448ba66e31c7ae518abe23be4e8f7d6723766e5d466d7fa30394306bcd4449a
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

        // <<<FAILED WITH ROUNDING ERROR PRIOR TO FIX>>>
        size = ud(500000000000000000);
        premiumLimit = scaleDecimals(ud(78646633752380059));
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);
        // <<<FAILED WITH ROUNDING ERROR PRIOR TO FIX>>>
        vm.stopPrank();
    }

    function test_trade_Sell500Options_WithApproval() public {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, address(0));

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell500Options_WithReferral() public {
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        uint256 initialCollateral;

        {
            UD60x18 _collateral = contractsToCollateral(UD60x18.wrap(depositSize));

            initialCollateral = scaleDecimals(_collateral * posKey.lower.avg(posKey.upper));
        }

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        uint256 collateral = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, uint256 takerFee) = pool.getQuoteAMM(users.trader, tradeSize, false);

        uint256 totalRebate;

        {
            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(takerFee);

            UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(takerFee);

            uint256 primaryRebate = scaleDecimals(_primaryRebate);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

            totalRebate = primaryRebate + secondaryRebate;
        }

        address token = getPoolToken();

        vm.startPrank(users.trader);

        deal(token, users.trader, collateral);
        IERC20(token).approve(address(router), collateral);

        pool.trade(tradeSize, false, totalPremium - totalPremium / 10, users.referrer);

        vm.stopPrank();

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);

        assertEq(IERC20(token).balanceOf(users.trader), totalPremium);
        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);

        assertEq(IERC20(token).balanceOf(address(pool)), initialCollateral + collateral - totalPremium - totalRebate);
    }

    function test_trade_RevertIf_BuyOptions_WithTotalPremiumAboveLimit() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, true);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, totalPremium, 0, totalPremium - 1)
        );
        pool.trade(tradeSize, true, totalPremium - 1, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithTotalPremiumBelowLimit() public {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        uint256 collateralScaled = scaleDecimals(contractsToCollateral(tradeSize));

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                totalPremium,
                totalPremium + 1,
                type(uint256).max
            )
        );
        pool.trade(tradeSize, false, totalPremium + 1, address(0));
    }

    function test_trade_RevertIf_BuyOptions_WithInsufficientAskLiquidity() public {
        posKey.orderType = Position.OrderType.CS;
        uint256 depositSize = 1000 ether;
        deposit(depositSize);

        vm.expectRevert(IPoolInternal.Pool__InsufficientAskLiquidity.selector);
        pool.trade(ud(depositSize + 1), true, 0, address(0));
    }

    function test_trade_RevertIf_SellOptions_WithInsufficientBidLiquidity() public {
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
}
