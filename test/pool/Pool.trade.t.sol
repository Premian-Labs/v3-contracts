// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IDiamondWritableInternal} from "@solidstate/contracts/proxy/diamond/writable/IDiamondWritableInternal.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {PoolTrade} from "contracts/pool/PoolTrade.sol";
import {IPoolTrade} from "contracts/pool/IPoolTrade.sol";
import {Premia} from "contracts/proxy/Premia.sol";
import {Referral} from "contracts/referral/Referral.sol";
import {ReferralProxy} from "contracts/referral/ReferralProxy.sol";
import {IPool} from "contracts/pool/IPool.sol";

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

    function test_trade_BuyOptions_HandleRoundingErrors_WithReferrals() public {
        // Rounding errors were discovered in Call Pool
        if (!poolKey.isCallPool) return;

        address token = getPoolToken();

        vm.startPrank(users.lp);

        {
            posKey.orderType = Position.OrderType.CS;
            posKey.lower = ud(0.134e18);
            posKey.upper = ud(0.135e18);
            UD60x18 depositSize = ud(0.333333333333333333e18);
            UD60x18 minMarketPrice = ZERO;
            UD60x18 maxMarketPrice = ONE;

            (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
                posKey.lower,
                posKey.upper
            );

            uint256 initialCollateral = scaleDecimals(poolKey.isCallPool ? depositSize : depositSize * poolKey.strike);
            deal(token, users.lp, initialCollateral);
            IERC20(token).approve(address(router), initialCollateral);
            pool.deposit(posKey, nearestBelowLower, nearestBelowUpper, depositSize, minMarketPrice, maxMarketPrice);
        }

        {
            posKey.orderType = Position.OrderType.CS;
            posKey.lower = ud(0.135e18);
            posKey.upper = ud(0.136e18);
            UD60x18 depositSize = ud(0.333333333333333333e18);
            UD60x18 minMarketPrice = ZERO;
            UD60x18 maxMarketPrice = ONE;

            (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
                posKey.lower,
                posKey.upper
            );

            uint256 initialCollateral = scaleDecimals(poolKey.isCallPool ? depositSize : depositSize * poolKey.strike);
            deal(token, users.lp, initialCollateral);
            IERC20(token).approve(address(router), initialCollateral);
            pool.deposit(posKey, nearestBelowLower, nearestBelowUpper, depositSize, minMarketPrice, maxMarketPrice);
        }

        vm.stopPrank();

        vm.startPrank(users.trader);

        // reverts without the fix
        UD60x18 size = ud(0.348000570389080836e18);
        (uint256 premiumLimit, ) = pool.getQuoteAMM(users.trader, size, true);
        deal(token, users.trader, premiumLimit);
        IERC20(token).approve(address(router), premiumLimit);
        pool.trade(size, true, premiumLimit, users.referrer);

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
