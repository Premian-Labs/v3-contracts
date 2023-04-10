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
    function deposit2(
        uint256 depositSize,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal returns (uint256 initialCollateral) {
        return
            deposit2(
                UD60x18.wrap(depositSize),
                UD60x18.wrap(lower),
                UD60x18.wrap(upper),
                orderType
            );
    }

    function deposit2(
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

    function test_hello_() public {
        // 1) liquidity zero in marked area (x):
        //          |------|xxxx|------|
        deposit2(1, 0.1 ether, 0.3 ether, Position.OrderType.LC);
        deposit2(1, 0.4 ether, 0.5 ether, Position.OrderType.CS);

        // create two non-overlapping CS and LC order
        // 2)
    }
}
