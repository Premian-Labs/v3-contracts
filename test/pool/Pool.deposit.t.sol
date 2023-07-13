// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Pricing} from "contracts/libraries/Pricing.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

abstract contract PoolDepositTest is DeployTest {
    function test_deposit_1000_LC_WithToken() public {
        poolKey.isCallPool = isCallTest;

        IERC20 token = IERC20(getPoolToken());
        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize);
        uint256 collateralValue = toTokenDecimals(collateral * avgPrice);

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(token.balanceOf(users.lp), initialCollateral - collateralValue);
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_CS_BelowMarketPrice() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        deposit(depositSize);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.005 ether),
            upper: ud(0.006 ether),
            orderType: Position.OrderType.CS
        });
        // need to mint 1.0 short options
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();

        IERC20 token = IERC20(getPoolToken());
        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, isCallTest ? ud(0.8445 ether) : ud(0.8445e9));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.2 ether);
        assertEq(pool.getCurrentTick(), 0.1 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 0.01 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
    }

    function test_deposit_CSUP_BelowMarketPrice() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        deposit(depositSize);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.005 ether),
            upper: ud(0.006 ether),
            orderType: Position.OrderType.CSUP
        });
        // need to mint 1.0 short options
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();

        IERC20 token = IERC20(getPoolToken());
        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, isCallTest ? ud(0.85 ether) : ud(0.85e9));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.2 ether);
        assertEq(pool.getCurrentTick(), 0.1 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 0.01 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
    }

    function test_deposit_LC_AboveMarketPrice() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.CS;

        uint256 depositSize = 1 ether;
        deposit(depositSize);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.3 ether),
            upper: ud(0.4 ether),
            orderType: Position.OrderType.LC
        });
        // need to mint 1.0 short options
        IERC20 token = IERC20(getPoolToken());
        uint256 balanceBefore = token.balanceOf(users.lp);
        pool.exposed_mint(users.lp, PoolStorage.LONG, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, balanceBefore);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.1 ether);
        assertEq(pool.getCurrentTick(), 0.001 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 0.0 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
    }

    function test_deposit_CS_Straddle() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        deposit(depositSize);
        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.15 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.CS
        });
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        IERC20 token = IERC20(getPoolToken());
        assertEq(token.balanceOf(users.lp), isCallTest ? 0.2625 ether : 262.500000e6);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(1.0 ether));
        assertEq(pool.marketPrice().unwrap(), 0.2 ether);
        // market price 0.2 -> current 0.1 -> next 0.15
        // reconcile -> cross 0.15
        assertEq(pool.getCurrentTick(), 0.15 ether);
        // reconcile -> kick in liquidity at tick 0.15
        assertEq(pool.getLiquidityRate().unwrap(), 0.02 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.01 ether);
    }

    function test_deposit_CS_StraddlePartiallyTraversed() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, false, depositSize);
        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.15 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.CS
        });
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(1.25 ether));
        assertEq(pool.marketPrice().unwrap(), 0.175 ether);
        // market price 0.175 -> current 0.1 -> next 0.15
        // reconcile -> cross 0.15
        assertEq(pool.getCurrentTick(), 0.15 ether);
        // reconcile -> kick in liquidity at tick 0.15
        assertEq(pool.getLiquidityRate().unwrap(), 0.02 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.01 ether);
    }

    function test_deposit_CSUP_Straddle() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        deposit(depositSize);
        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.15 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.CSUP
        });
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(1.0 ether));
        assertEq(pool.marketPrice().unwrap(), 0.2 ether);
        // market price 0.2 -> current 0.1 -> next 0.15
        // reconcile -> cross 0.15
        assertEq(pool.getCurrentTick(), 0.15 ether);
        // reconcile -> kick in liquidity at tick 0.15
        assertEq(pool.getLiquidityRate().unwrap(), 0.02 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.01 ether);
    }

    function test_deposit_CSUP_StraddlePartiallyTraversed() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;

        uint256 depositSize = 1 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, false, depositSize);
        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.15 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.CSUP
        });
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(1.25 ether));
        assertEq(pool.marketPrice().unwrap(), 0.175 ether);
        // market price 0.175 -> current 0.1 -> next 0.15
        // reconcile -> cross 0.15
        assertEq(pool.getCurrentTick(), 0.15 ether);
        // reconcile -> kick in liquidity at tick 0.15
        assertEq(pool.getLiquidityRate().unwrap(), 0.02 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.01 ether);
    }

    function test_deposit_LC_Straddle() public {
        posKey.lower = ud(0.15 ether);
        posKey.upper = ud(0.25 ether);
        posKey.orderType = Position.OrderType.CS;

        uint256 depositSize = 1 ether;
        deposit(depositSize);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.1 ether),
            upper: ud(0.2 ether),
            orderType: Position.OrderType.LC
        });
        // need to mint 1.0 short options
        IERC20 token = IERC20(getPoolToken());
        uint256 initialCollateral = toTokenDecimals(isCallTest ? ud(depositSize) : ud(depositSize) * poolKey.strike);
        deal(address(token), users.lp, initialCollateral);
        pool.exposed_mint(users.lp, PoolStorage.LONG, ud(1.5 ether));
        vm.startPrank(users.lp);
        token.approve(address(router), initialCollateral);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(token.balanceOf(users.lp), isCallTest ? (1 ether - 0.0625 ether) : (1e9 - 0.0625e9));
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(1.0 ether));
        assertEq(pool.marketPrice().unwrap(), 0.15 ether);
        // market price 0.15 -> current 0.01 -> next 0.1
        // reconcile -> cross 0.1
        assertEq(pool.getCurrentTick(), 0.1 ether);
        // cross kicks in liquidity from the LC order, however not from the CS order
        assertEq(pool.getLiquidityRate().unwrap(), 0.01 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
    }

    function test_deposit_LC_StraddlePartiallyTraversed() public {
        posKey.lower = ud(0.15 ether);
        posKey.upper = ud(0.25 ether);
        posKey.orderType = Position.OrderType.CS;

        uint256 depositSize = 1 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, true, depositSize);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.1 ether),
            upper: ud(0.2 ether),
            orderType: Position.OrderType.LC
        });
        // need to mint 1.0 short options
        IERC20 token = IERC20(getPoolToken());
        uint256 initialCollateral = toTokenDecimals(isCallTest ? ud(depositSize) : ud(depositSize) * poolKey.strike);
        deal(address(token), users.lp, initialCollateral);
        pool.exposed_mint(users.lp, PoolStorage.LONG, ud(1.5 ether));
        vm.startPrank(users.lp);
        token.approve(address(router), initialCollateral);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(1.25 ether));
        assertEq(pool.marketPrice().unwrap(), 0.175 ether);
        // market price 0.175 -> current 0.15
        // reconcile -> no crossing
        assertEq(pool.getCurrentTick(), 0.15 ether);
        // liquidity from the LC order should be added during deposit
        assertEq(pool.getLiquidityRate().unwrap(), 0.02 ether);
        assertEq(pool.getLongRate(), 0.01 ether);
        assertEq(pool.getShortRate(), 0.01 ether);
    }

    function test_deposit_CS_isBidIfStrandedMarketPrice_True() public {
        // deposit CS order with isBidIfStrandedMarketPrice set to True
        uint256 depositSize = 1 ether;

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.005 ether),
            upper: ud(0.006 ether),
            orderType: Position.OrderType.CS
        });
        // need to mint 1.0 short options
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        uint256 initialCollateral = toTokenDecimals(isCallTest ? ud(depositSize) : ud(depositSize) * poolKey.strike);
        deal(getPoolToken(), users.lp, initialCollateral);
        IERC20 token = IERC20(getPoolToken());
        vm.startPrank(users.lp);
        token.approve(address(router), initialCollateral);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE, true);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, isCallTest ? ud(0.9945 ether) : ud(0.9945e9));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.006 ether);
        assertEq(pool.getCurrentTick(), 0.005 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 1 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 1 ether);
    }

    function test_deposit_CSUP_isBidIfStrandedMarketPrice_True() public {
        // deposit CSUP order with isBidIfStrandedMarketPrice set to True
        uint256 depositSize = 1 ether;

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.005 ether),
            upper: ud(0.006 ether),
            orderType: Position.OrderType.CSUP
        });
        // need to mint 1.0 short options
        pool.exposed_mint(users.lp, PoolStorage.SHORT, ud(1.5 ether));
        uint256 initialCollateral = toTokenDecimals(isCallTest ? ud(depositSize) : ud(depositSize) * poolKey.strike);
        deal(getPoolToken(), users.lp, initialCollateral);
        IERC20 token = IERC20(getPoolToken());
        vm.startPrank(users.lp);
        token.approve(address(router), initialCollateral);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE, true);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, isCallTest ? ud(1 ether) : ud(1e9));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.006 ether);
        assertEq(pool.getCurrentTick(), 0.005 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 1 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 1 ether);
    }

    function test_deposit_LC_isBidIfStrandedMarketPrice_False() public {
        // deposit LC order with isBidIfStrandedMarketPrice set to false
        uint256 depositSize = 1 ether;
        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.3 ether),
            upper: ud(0.4 ether),
            orderType: Position.OrderType.LC
        });
        // need to mint 1.0 short options
        IERC20 token = IERC20(getPoolToken());
        uint256 balanceBefore = token.balanceOf(users.lp);
        pool.exposed_mint(users.lp, PoolStorage.LONG, ud(1.5 ether));
        vm.startPrank(users.lp);
        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(
            customPosKey.lower,
            customPosKey.upper
        );
        pool.deposit(customPosKey, nearestBelowLower, nearestBelowUpper, ud(depositSize), ZERO, ONE, false);
        vm.stopPrank();

        uint256 balanceAfter = token.balanceOf(users.lp);
        assertEq(balanceAfter, balanceBefore);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(0.5 ether));
        assertEq(pool.marketPrice().unwrap(), 0.3 ether);
        assertEq(pool.getCurrentTick(), 0.001 ether);
        assertEq(pool.getLiquidityRate().unwrap(), 0.0 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
    }

    function _setup_CS() public {
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.25 ether),
            upper: ud(0.75 ether),
            orderType: Position.OrderType.CS
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.0 ether));
        assertEq(pool.getCurrentTick(), ud(0.001 ether));
        assertEq(pool.marketPrice(), ud(0.25 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(ud(0.25 ether));
        assertEq(tick0.delta.unwrap(), 0.002 ether);
        assertEq(tick0.shortDelta.unwrap(), 0.002 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(ud(0.75 ether));
        assertEq(tick1.delta.unwrap(), -0.002 ether);
        assertEq(tick1.shortDelta.unwrap(), -0.002 ether);
    }

    function _setup_LC() public {
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.25 ether),
            upper: ud(0.75 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.25 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(ud(0.25 ether));
        assertEq(tick0.delta.unwrap(), -0.002 ether);
        assertEq(tick0.longDelta.unwrap(), -0.002 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(ud(0.75 ether));
        assertEq(tick1.delta.unwrap(), -0.002 ether);
        assertEq(tick1.longDelta.unwrap(), -0.002 ether);
    }

    function test_deposit_Case1() public {
        _setup_LC();
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.01 ether),
            upper: ud(0.05 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.25 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(ud(0.01 ether));
        assertEq(tick0.delta.unwrap(), -0.025 ether);
        assertEq(tick0.longDelta.unwrap(), -0.025 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(ud(0.05 ether));
        assertEq(tick1.delta.unwrap(), 0.025 ether);
        assertEq(tick1.longDelta.unwrap(), 0.025 ether);
    }

    function test_deposit_Case2() public {
        _setup_LC();
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.05 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.25 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.005 ether);
        assertEq(tick0.longDelta.unwrap(), -0.005 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), 0.003 ether);
        assertEq(tick1.longDelta.unwrap(), 0.003 ether);
    }

    function test_deposit_Case3() public {
        _setup_LC();
        // liq per tick of position is 0.004
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.25 ether),
            upper: ud(0.5 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.5 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.006 ether);
        assertEq(tick0.longDelta.unwrap(), -0.006 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), 0.004 ether);
        assertEq(tick1.longDelta.unwrap(), 0.004 ether);
    }

    function test_deposit_Case4() public {
        _setup_LC();
        // liq per tick of position is 0.005
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.3 ether),
            upper: ud(0.5 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.5 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.005 ether);
        assertEq(tick0.longDelta.unwrap(), -0.005 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), 0.005 ether);
        assertEq(tick1.longDelta.unwrap(), 0.005 ether);
    }

    function test_deposit_Case5() public {
        _setup_LC();
        // liq per tick of position is 0.0025
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.35 ether),
            upper: ud(0.75 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.0045 ether));
        assertEq(pool.getCurrentTick(), ud(0.35 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.0025 ether);
        assertEq(tick0.longDelta.unwrap(), -0.0025 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.0045 ether);
        assertEq(tick1.longDelta.unwrap(), -0.0045 ether);
    }

    function test_deposit_Case6() public {
        _setup_LC();
        // liq per tick of position is 0.02
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.75 ether),
            upper: ud(0.8 ether),
            orderType: Position.OrderType.CS
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.002 ether));
        assertEq(pool.getCurrentTick(), ud(0.25 ether));
        assertEq(pool.marketPrice(), ud(0.75 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), 0.018 ether);
        assertEq(tick0.shortDelta.unwrap(), 0.02 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.02 ether);
        assertEq(tick1.shortDelta.unwrap(), -0.02 ether);
    }

    function test_deposit_Case7() public {
        _setup_LC();
        // liq per tick of position is 0.05
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.78 ether),
            upper: ud(0.8 ether),
            orderType: Position.OrderType.CS
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.0 ether));
        assertEq(pool.getCurrentTick(), ud(0.75 ether));
        assertEq(pool.marketPrice(), ud(0.78 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), 0.05 ether);
        assertEq(tick0.shortDelta.unwrap(), 0.05 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.05 ether);
        assertEq(tick1.shortDelta.unwrap(), -0.05 ether);
    }

    function test_deposit_Case8() public {
        _setup_CS();
        // liq per tick of position is 0.025
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.01 ether),
            upper: ud(0.05 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.025 ether));
        assertEq(pool.getCurrentTick(), ud(0.01 ether));
        assertEq(pool.marketPrice(), ud(0.05 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.025 ether);
        assertEq(tick0.longDelta.unwrap(), -0.025 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.025 ether);
        assertEq(tick1.longDelta.unwrap(), -0.025 ether);
    }

    function test_deposit_Case9() public {
        _setup_CS();
        // liq per tick of position is 0.005
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.05 ether),
            upper: ud(0.25 ether),
            orderType: Position.OrderType.LC
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.005 ether));
        assertEq(pool.getCurrentTick(), ud(0.05 ether));
        assertEq(pool.marketPrice(), ud(0.25 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), -0.005 ether);
        assertEq(tick0.longDelta.unwrap(), -0.005 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.003 ether);
        assertEq(tick1.longDelta.unwrap(), -0.005 ether);
    }

    function test_deposit_Case10() public {
        _setup_CS();
        // liq per tick of position is 0.004
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.25 ether),
            upper: ud(0.5 ether),
            orderType: Position.OrderType.CS
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.0 ether));
        assertEq(pool.getCurrentTick(), ud(0.001 ether));
        assertEq(pool.marketPrice(), ud(0.25 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), 0.006 ether);
        assertEq(tick0.shortDelta.unwrap(), 0.006 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.004 ether);
        assertEq(tick1.shortDelta.unwrap(), -0.004 ether);
    }

    function test_deposit_Case11() public {
        _setup_CS();
        // liq per tick of position is 0.005
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.3 ether),
            upper: ud(0.5 ether),
            orderType: Position.OrderType.CS
        });
        deposit(customPosKey0, ud(1 ether));
        assertEq(pool.getLiquidityRate(), ud(0.0 ether));
        assertEq(pool.getCurrentTick(), ud(0.001 ether));
        assertEq(pool.marketPrice(), ud(0.25 ether));
        IPoolInternal.Tick memory tick0 = pool.exposed_getTick(customPosKey0.lower);
        assertEq(tick0.delta.unwrap(), 0.005 ether);
        assertEq(tick0.shortDelta.unwrap(), 0.005 ether);
        IPoolInternal.Tick memory tick1 = pool.exposed_getTick(customPosKey0.upper);
        assertEq(tick1.delta.unwrap(), -0.005 ether);
        assertEq(tick1.shortDelta.unwrap(), -0.005 ether);
    }

    function test_deposit_RevertIf_SenderNotOperator() public {
        posKey.operator = users.trader;

        vm.prank(users.lp);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.lp));

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_MarketPriceOutOfMinMax() public {
        poolKey.isCallPool = isCallTest;
        deposit(1000 ether);
        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        UD60x18 minPrice = posKey.upper + ud(1);
        UD60x18 maxPrice = posKey.upper;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.deposit(posKey, ZERO, ZERO, THREE, minPrice, maxPrice);

        minPrice = posKey.upper - ud(10);
        maxPrice = posKey.upper - ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.deposit(posKey, ZERO, ZERO, THREE, minPrice, maxPrice);
    }

    function test_deposit_RevertIf_ZeroSize() public {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);

        pool.deposit(posKey, ZERO, ZERO, ZERO, ZERO, ONE);
    }

    function test_deposit_RevertIf_Expired() public {
        vm.prank(users.lp);

        vm.warp(poolKey.maturity + 1);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = ud(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(1.01e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ud(0.2501e18);
        posKey.upper = ud(0.7501e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__TickWidthInvalid.selector, posKey.lower));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(0.7501e18);
        // we won't catch the second tickWidth revert as there is no way to define a valid lower and an invalid upper
        // without having an invalid range
        vm.expectRevert();
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_InvalidSize() public {
        uint256 depositSize = 1 ether + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, posKey.lower, posKey.upper, depositSize)
        );
        vm.startPrank(users.lp);
        pool.deposit(posKey, ZERO, ZERO, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        depositSize = 1 ether + 199;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, posKey.lower, posKey.upper, depositSize)
        );
        vm.startPrank(users.lp);
        pool.deposit(posKey, ZERO, ZERO, ud(depositSize), ZERO, ONE);
        vm.stopPrank();
        // this one below is expected to pass as the range order has a width of 200 ticks
        depositSize = 1 ether + 200;
        deposit(depositSize);
    }

    function test_ticks_ReturnExpectedValues() public {
        deposit(1000 ether);

        IPoolInternal.TickWithRates[] memory ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, posKey.lower);
        assertEq(ticks[2].price, posKey.upper);
        assertEq(ticks[3].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].longRate, ZERO);
        assertEq(ticks[1].longRate, ud(5 ether));
        assertEq(ticks[2].longRate, ZERO);
        assertEq(ticks[3].longRate, ZERO);

        Position.Key memory customPosKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.2 ether),
            upper: ud(0.3 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey, ud(1000 ether));

        ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, posKey.lower);
        assertEq(ticks[2].price, customPosKey.lower);
        assertEq(ticks[3].price, posKey.upper);
        assertEq(ticks[4].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].longRate, ZERO);
        assertEq(ticks[1].longRate, ud(5 ether));
        assertEq(ticks[2].longRate, ud(15 ether));
        assertEq(ticks[3].longRate, ZERO);
        assertEq(ticks[4].longRate, ZERO);
    }

    function test_ticks_NoDeposit() public {
        IPoolInternal.TickWithRates[] memory ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].longRate, ZERO);
        assertEq(ticks[0].shortRate, ZERO);
        assertEq(ticks[1].longRate, ZERO);
        assertEq(ticks[1].shortRate, ZERO);
    }

    function test_ticks_DepositMinTick() public {
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.001 ether),
            upper: ud(0.005 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey0, ud(200 ether));

        Position.Key memory customPosKey1 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.005 ether),
            upper: ud(0.009 ether),
            orderType: Position.OrderType.CS
        });

        deposit(customPosKey1, ud(10 ether));

        IPoolInternal.TickWithRates[] memory ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, customPosKey0.upper);
        assertEq(ticks[2].price, customPosKey1.upper);
        assertEq(ticks[3].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].longRate, ud(50 ether));
        assertEq(ticks[1].longRate, ZERO);
        assertEq(ticks[2].longRate, ZERO);
        assertEq(ticks[0].shortRate, ZERO);
        assertEq(ticks[1].shortRate, ud(2.5 ether));
        assertEq(ticks[2].shortRate, ZERO);
        assertEq(ticks[3].shortRate, ZERO);
    }

    function test_ticks_ThreeDeposits() public {
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.001 ether),
            upper: ud(0.002 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey0, ud(40 ether));

        Position.Key memory customPosKey1 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.2 ether),
            upper: ud(0.4 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey1, ud(10 ether));

        Position.Key memory customPosKey2 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.2 ether),
            upper: ud(0.6 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey2, ud(100 ether));

        Position.Key memory customPosKey3 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.6 ether),
            upper: ud(0.8 ether),
            orderType: Position.OrderType.CS
        });

        deposit(customPosKey3, ud(10 ether));

        IPoolInternal.TickWithRates[] memory ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, customPosKey0.upper);
        assertEq(ticks[2].price, customPosKey1.lower);
        assertEq(ticks[3].price, customPosKey1.upper);
        assertEq(ticks[4].price, customPosKey2.upper);
        assertEq(ticks[5].price, customPosKey3.upper);
        assertEq(ticks[6].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].longRate, ud(40 ether));
        assertEq(ticks[0].shortRate, ZERO);
        // lr (0.002 - 0.2)
        assertEq(ticks[1].longRate, ud(0 ether));
        assertEq(ticks[1].shortRate, ZERO);
        // lr (0.2 and 0.4)
        // 10 / 200 + (100 / 400) = 0.3
        // total liquidity is numTicks * liqRate = 200 * 0.3 = 60
        assertEq(ticks[2].longRate, ud(0.3 ether));
        assertEq(ticks[2].shortRate, ZERO);
        // lr (0.4 and 0.6)
        // total liquidity is numTicks * liqRate = 200 * 0.25 = 50
        assertEq(ticks[3].longRate, ud(0.25 ether));
        assertEq(ticks[3].shortRate, ZERO);
        // lr (0.6 and 0.8)
        assertEq(ticks[4].longRate, ZERO);
        assertEq(ticks[4].shortRate, ud(0.05 ether));
        // lr (0.8 and 1.0)
        assertEq(ticks[5].longRate, ZERO);
        assertEq(ticks[5].shortRate, ZERO);
    }

    function test_getNearestTicksBelow_MaxTickPrice() public {
        (UD60x18 belowLower, UD60x18 belowUpper) = pool.getNearestTicksBelow(ud(0.998 ether), ud(1 ether));
        assertEq(belowLower, ud(0.001 ether));
        assertEq(belowUpper, ud(1 ether));
    }

    function test_getNearestTicksBelow_MinTickPrice() public {
        (UD60x18 belowLower, UD60x18 belowUpper) = pool.getNearestTicksBelow(ud(0.001 ether), ud(0.005 ether));
        assertEq(belowLower, ud(0.001 ether));
        assertEq(belowUpper, ud(0.001 ether));
    }

    function test_getNearestTicksBelow_LowerIsBelowUpper() public {
        (UD60x18 belowLower, UD60x18 belowUpper) = pool.getNearestTicksBelow(ud(0.002 ether), ud(0.802 ether));
        assertEq(belowLower, ud(0.001 ether));
        assertEq(belowUpper, ud(0.002 ether));
    }

    function test_getNearestTicksBelow_OneDeposit() public {
        Position.Key memory customPosKey0 = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.002 ether),
            upper: ud(0.004 ether),
            orderType: Position.OrderType.LC
        });

        deposit(customPosKey0, ud(40 ether));

        (UD60x18 belowLower, UD60x18 belowUpper) = pool.getNearestTicksBelow(ud(0.003 ether), ud(0.013 ether));
        assertEq(belowLower, ud(0.002 ether));
        assertEq(belowUpper, ud(0.004 ether));
    }

    function test_getNearestTicksBelow_RevertIf_InvalidRange() public {
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, ud(0.001 ether), ud(2 ether))
        );
        pool.getNearestTicksBelow(ud(0.001 ether), ud(2 ether));
    }

    function test_isRateNonTerminating() public {
        // Test that 1 = 2^0*5^0 is terminating
        bool result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.002 ether));
        assertFalse(result);

        // Test that 2 = 2^1*5^0 is terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.003 ether));
        assertFalse(result);

        // Test that 8 = 2^3*5^0 is terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.009 ether));
        assertFalse(result);

        // Test that 10 = 2^1*5^1 is terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.011 ether));
        assertFalse(result);

        // Test that 20 = 2^2*5^1 is terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.021 ether));
        assertFalse(result);

        // Test that 25 = 2^0*5^2 is terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.026 ether));
        assertFalse(result);

        // Test that 3 is non-terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.004 ether));
        assertTrue(result);

        // Test that 7 is non-terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.008 ether));
        assertTrue(result);

        // Test that 9 is non-terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.010 ether));
        assertTrue(result);

        // Test that 28 is non-terminating
        result = pool.exposed_isRateNonTerminating(ud(0.001 ether), ud(0.029 ether));
        assertTrue(result);
    }
}
