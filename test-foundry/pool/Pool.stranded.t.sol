// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolStrandedTest is DeployTest {
    function deposit_specified(
        uint256 depositSize,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        return
            deposit_specified(
                UD60x18.wrap(depositSize),
                UD60x18.wrap(lower),
                UD60x18.wrap(upper),
                orderType
            );
    }

    function deposit_specified(
        UD60x18 depositSize,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        bool isCall = poolKey.isCallPool;

        IERC20 token = IERC20(getPoolToken(isCall));
        initialCollateral = scaleDecimals(
            isCall ? depositSize : depositSize * poolKey.strike,
            isCall
        );

        vm.startPrank(users.lp);

        deal(address(token), users.lp, initialCollateral);
        token.approve(address(router), initialCollateral);

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: lower,
            upper: upper,
            orderType: orderType
        });

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        pool.deposit(
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            depositSize,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        vm.stopPrank();
    }

    function withdraw_specified(
        uint256 withdrawSize,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        return
            withdraw_specified(
                UD60x18.wrap(withdrawSize),
                UD60x18.wrap(lower),
                UD60x18.wrap(upper),
                orderType
            );
    }

    function withdraw_specified(
        UD60x18 withdrawSize,
        UD60x18 lower,
        UD60x18 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        bool isCall = poolKey.isCallPool;

        IERC20 token = IERC20(getPoolToken(isCall));
        initialCollateral = scaleDecimals(
            isCall ? withdrawSize : withdrawSize * poolKey.strike,
            isCall
        );

        vm.startPrank(users.lp);

        posKey = Position.Key({
            owner: users.lp,
            operator: users.lp,
            lower: lower,
            upper: upper,
            orderType: orderType
        });

        pool.withdraw(
            posKey,
            withdrawSize,
            UD60x18.wrap(0.001 ether),
            UD60x18.wrap(1 ether)
        );

        vm.stopPrank();
    }

    function test_stranded_zero_liquidity_empty_pool() public {
        // - zero liquidity area marked with (x)
        // - non-zero liquidity area marked with (L)
        //          |xxxxxxxxxxxxxxxxxxxxxxx|
        assertEq(pool.get_liquidityRate(), 0 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.001 ether);
        assertEq(upper.unwrap(), 1 ether);
    }

    function test_stranded_zero_liquidity_two_deposits() public {
        // - zero liquidity area marked with (x)
        // - non-zero liquidity area marked with (L)
        //
        //                 market price (0.4)
        //                 right tick of current (0.4)
        //                       v
        //          |---|LLL|xxxx|LLL|------|
        //                  ^
        //             current tick (0.3)

        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        assertEq(pool.get_liquidityRate(), 0 ether);
        assertEq(pool.marketPrice(), 0.4 ether);

        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_zero_liquidity_market_price_within() public {
        // - zero liquidity area marked with (x)
        // - non-zero liquidity area marked with (L)
        //             market price (0.35)
        //                    v
        //                 right tick of current (0.4)
        //                       v
        //          |---|LLL|xxxx|LLL|------|
        //                  ^
        //             current tick (0.3)
        vm.warp(0);
        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        deposit_specified(
            1 ether,
            0.35 ether,
            0.4 ether,
            Position.OrderType.CS
        );
        vm.warp(600);
        withdraw_specified(
            1 ether,
            0.35 ether,
            0.4 ether,
            Position.OrderType.CS
        );
        assertEq(pool.get_liquidityRate(), 0 ether);
        assertEq(pool.marketPrice(), 0.35 ether);

        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_bid_bound_price_single_deposit() public {
        //            market price (0.3)
        //                      v
        //          |-------|LLL|------|
        //                  ^
        //             current tick (0.1)
        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        UD60x18 currentTick = pool.get_currentTick();
        assertEq(currentTick, 0.1 ether);
        assertEq(pool.marketPrice(), 0.3 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 1.0 ether);
    }

    function test_stranded_ask_bound_price_single_deposit() public {
        //            market price (0.4)
        //                  v
        //          |-------|LLL|------|
        //                  ^
        //             current tick (0.4)
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        pool.exposed_cross(true);
        UD60x18 currentTick = pool.get_currentTick();
        assertEq(currentTick, 0.4 ether);
        assertEq(pool.marketPrice(), 0.4 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.001 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_bid_bound_price_two_deposits() public {
        //            market price (0.3)
        //                      v
        //          |-------|LLL|--|LLL|----|
        //                  ^
        //             current tick (0.1)
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        UD60x18 currentTick = pool.get_currentTick();
        assertEq(currentTick, 0.1 ether);
        assertEq(pool.marketPrice(), 0.3 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_ask_bound_price_two_deposits() public {
        //                 market price (0.4)
        //                       v
        //          |-----|LLL|--|LLL|------|
        //                       ^
        //                 current tick (0.4)
        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        pool.exposed_cross(true);
        UD60x18 currentTick = pool.get_currentTick();
        assertEq(currentTick, 0.4 ether);
        assertEq(pool.marketPrice(), 0.4 ether);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();
        assertEq(lower.unwrap(), 0.3 ether);
        assertEq(upper.unwrap(), 0.4 ether);
    }

    function test_stranded_isMarketPriceStranded() public {
        deposit_specified(1 ether, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        deposit_specified(1 ether, 0.4 ether, 0.5 ether, Position.OrderType.CS);
        (UD60x18 lower, UD60x18 upper) = pool.exposed_getStrandedArea();

        Position.KeyInternal memory posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.002 ether),
            upper: UD60x18.wrap(0.32 ether),
            orderType: Position.OrderType.LC,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        bool isStranded = pool.exposed_isMarketPriceStranded(
            posKeyInternal,
            true
        );
        assertEq(isStranded, true);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.002 ether),
            upper: UD60x18.wrap(0.28 ether),
            orderType: Position.OrderType.LC,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, true);
        assertEq(isStranded, false);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.38 ether),
            upper: UD60x18.wrap(0.7 ether),
            orderType: Position.OrderType.CS,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });

        isStranded = pool.exposed_isMarketPriceStranded(posKeyInternal, false);
        assertEq(isStranded, true);

        posKeyInternal = Position.KeyInternal({
            owner: users.lp,
            operator: users.lp,
            lower: UD60x18.wrap(0.48 ether),
            upper: UD60x18.wrap(0.7 ether),
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
            lower: UD60x18.wrap(0.48 ether),
            upper: UD60x18.wrap(0.7 ether),
            orderType: Position.OrderType.CS,
            strike: poolKey.strike,
            isCall: poolKey.isCallPool
        });
        UD60x18 price = pool.exposed_getStrandedMarketPriceUpdate(
            posKeyInternal,
            true
        );
        assertEq(price.unwrap(), 0.7 ether);

        price = pool.exposed_getStrandedMarketPriceUpdate(
            posKeyInternal,
            false
        );
        assertEq(price.unwrap(), 0.48 ether);
    }
}
