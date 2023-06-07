// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";
import {console} from "forge-std/console.sol";

abstract contract PoolStrandedTest is DeployTest {
    function depositSpecified(
        uint256 depositSize,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        return depositSpecified(ud(depositSize), ud(lower), ud(upper), orderType);
    }

    function depositSpecified(
        UD60x18 depositSize,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        IERC20 token = IERC20(getPoolToken());
        initialCollateral = scaleDecimals(isCallTest ? depositSize : depositSize * poolKey.strike);

        vm.startPrank(users.lp);

        deal(address(token), users.lp, initialCollateral);
        token.approve(address(router), initialCollateral);

        posKey = Position.Key({owner: users.lp, operator: users.lp, lower: lower, upper: upper, orderType: orderType});

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool.getNearestTicksBelow(posKey.lower, posKey.upper);

        pool.deposit(posKey, nearestBelowLower, nearestBelowUpper, depositSize, ZERO, ONE);

        vm.stopPrank();
    }

    function withdrawSpecified(
        uint256 withdrawSize,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        return withdrawSpecified(ud(withdrawSize), ud(lower), ud(upper), orderType);
    }

    function withdrawSpecified(
        UD60x18 withdrawSize,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        initialCollateral = scaleDecimals(isCallTest ? withdrawSize : withdrawSize * poolKey.strike);

        vm.startPrank(users.lp);

        posKey = Position.Key({owner: users.lp, operator: users.lp, lower: lower, upper: upper, orderType: orderType});

        pool.withdraw(posKey, withdrawSize, ud(0.001 ether), ud(1 ether));

        vm.stopPrank();
    }

    function test_stranded_ZeroLiquidity_EmptyPool() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //          |ZZZZZZZZZZZZZZZZZZZZZZZZZZ|
        //          ^
        //  current tick (0.001)
        assertEq(pool.getLiquidityRate(), 0 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.001 ether);
        assertEq(upper.unwrap(), 1 ether);
    }

    function test_stranded_ZeroLiquidity_TwoDeposits() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //
        //                  market price (0.4)
        //                  right tick of current (0.4)
        //                         v
        //          |-------|LLL|ZZ|LLL|-------|
        //                      ^
        //             current tick (0.3)

        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        assertEq(pool.getLiquidityRate(), 0 ether);
        assertEq(pool.marketPrice(), 0.4 ether);

        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_ZeroLiquidity_MarketPriceWithinStrandedArea() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //               market price (0.35)
        //                       v
        //                 right tick of current (0.4)
        //                         v
        //          |-------|LLL|ZZ|LLL|-------|
        //                      ^
        //             current tick (0.3)
        vm.warp(0);
        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        depositSpecified(1 ether, 0.35 ether, 0.4 ether, Position.OrderType.CS);
        vm.warp(600);
        withdrawSpecified(1 ether, 0.35 ether, 0.4 ether, Position.OrderType.CS);
        assertEq(pool.getLiquidityRate(), 0 ether);
        assertEq(pool.marketPrice(), 0.35 ether);

        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_BidBoundPrice_OneDeposit() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //            market price (0.3)
        //                      v
        //          |-------|LLL|ZZZZZZZ|
        //                  ^
        //             current tick (0.1)
        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        UD60x18 currentTick = pool.getCurrentTick();
        assertEq(currentTick, 0.1 ether);
        assertEq(pool.marketPrice(), 0.3 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 1.0 ether);
    }

    function test_stranded_AskBoundPrice_OneDeposit() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //            market price (0.4)
        //                  v
        //          |ZZZZZZZ|LLL|-------|
        //                  ^
        //             current tick (0.4)
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        pool.exposed_cross(true);
        UD60x18 currentTick = pool.getCurrentTick();
        assertEq(currentTick, 0.4 ether);
        assertEq(pool.marketPrice(), 0.4 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.001 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_BidBoundPrice_TwoDeposits() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //            market price (0.3)
        //                      v
        //          |-------|LLL|ZZ|LLL|----|
        //                  ^
        //             current tick (0.1)
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        UD60x18 currentTick = pool.getCurrentTick();
        assertEq(currentTick, 0.1 ether);
        assertEq(pool.marketPrice(), 0.3 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_AskBoundPrice_TwoDeposits() public {
        // - zero liquidity area marked with (Z)
        // - non-zero liquidity area marked with (L)
        //                 market price (0.4)
        //                       v
        //          |-----|LLL|--|LLL|------|
        //                       ^
        //                 current tick (0.4)
        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        pool.exposed_cross(true);
        UD60x18 currentTick = pool.getCurrentTick();
        assertEq(currentTick, 0.4 ether);
        assertEq(pool.marketPrice(), 0.4 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_isMarketPriceStranded() public {
        depositSpecified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);

        Position.KeyInternal memory posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.002 ether),
            upper: ud(0.32 ether),
            orderType: Position.OrderType.LC,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        bool isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, true);
        assertEq(isStranded, true);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.002 ether),
            upper: ud(0.28 ether),
            orderType: Position.OrderType.LC,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, true);
        assertEq(isStranded, false);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.38 ether),
            upper: ud(0.7 ether),
            orderType: Position.OrderType.CS,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, false);
        assertEq(isStranded, true);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.48 ether),
            upper: ud(0.7 ether),
            orderType: Position.OrderType.CS,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, false);
        assertEq(isStranded, false);
    }

    function test_stranded_getStrandedMarketPriceUpdate() public {
        Position.KeyInternal memory posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: ud(0.48 ether),
            upper: ud(0.7 ether),
            orderType: Position.OrderType.CS,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });
        UD60x18 price = pool.exposed_getStrandedMarketPriceUpdate(posKeyInternal, true);
        assertEq(price.unwrap(), 0.7 ether);

        price = pool.exposed_getStrandedMarketPriceUpdate(posKeyInternal, false);
        assertEq(price.unwrap(), 0.48 ether);
    }

    function test_stranded_noStrandedMarketArea_StrandedPricesCoincide() public {
        depositSpecified(1 ether, 0.1 ether, 0.4 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        // has to hold for downstream functionality
        assertEq(lower.unwrap(), upper.unwrap());
    }

    function test_stranded_noStrandedMarketArea_LCCS() public {
        depositSpecified(1 ether, 0.1 ether, 0.4 ether, Position.OrderType.LC);
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 2 ether);
        assertEq(upper.unwrap(), 2 ether);
    }

    function test_stranded_noStrandedMarketArea_CSLC() public {
        depositSpecified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        depositSpecified(1 ether, 0.1 ether, 0.4 ether, Position.OrderType.LC);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 2 ether);
        assertEq(upper.unwrap(), 2 ether);
    }

    function test_stranded_noStrandedMarketAreaPartiallyTraversedOrder() public {
        uint256 depositSize = 2 ether;
        uint256 tradeSize = 1 ether;
        trade(tradeSize, true, depositSize);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 2 ether);
        assertEq(upper.unwrap(), 2 ether);
    }

    function test_stranded_noStrandedMarketAreaFullyTraversedOrder_MaxTick() public {
        uint256 tradeSize = 1 ether;
        posKey.lower = ud(0.999 ether);
        posKey.upper = ud(1 ether);
        trade(tradeSize, true);
        assertEq(pool.marketPrice(), ud(1 ether));
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 2 ether);
        assertEq(upper.unwrap(), 2 ether);
    }

    function test_stranded_noStrandedMarketAreaFullyTraversedOrder_MinTick() public {
        uint256 tradeSize = 1 ether;
        posKey.lower = ud(0.001 ether);
        posKey.upper = ud(0.101 ether);
        trade(tradeSize, false);
        assertEq(pool.marketPrice(), ud(0.001 ether));
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 2 ether);
        assertEq(upper.unwrap(), 2 ether);
    }

    function test_stranded_strandedMarketAreaFullyTraversedOrder_Sell() public {
        uint256 tradeSize = 1 ether;
        posKey.lower = ud(0.002 ether);
        posKey.upper = ud(0.102 ether);
        trade(tradeSize, false);
        assertEq(pool.marketPrice(), ud(0.002e18));
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.001 ether);
        assertEq(upper.unwrap(), 0.002 ether);
    }

    function test_stranded_strandedMarketAreaFullyTraversedOrder_Buy() public {
        uint256 tradeSize = 1 ether;
        posKey.lower = ud(0.002 ether);
        posKey.upper = ud(0.102 ether);
        trade(tradeSize, true);
        assertEq(pool.marketPrice(), ud(0.102e18));
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.102 ether);
        assertEq(upper.unwrap(), 1 ether);
    }
}
