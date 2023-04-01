// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSwapAndDepositTest is DeployTest {
    function _test_swapAndDeposit_Success(bool isCall) internal {
        address swapToken = getSwapToken(isCall);
        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.lp);

        UD60x18 depositSize = THREE;

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        uint256 swapQuote = getSwapQuoteExactOutput(
            swapToken,
            poolToken,
            collateralValue
        );

        deal(swapToken, users.lp, swapQuote);

        IERC20(swapToken).approve(address(router), type(uint256).max);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            poolToken,
            swapQuote,
            collateralValue,
            users.lp
        );

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        pool.swapAndDeposit(
            swapArgs,
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize,
            "pool balance"
        );
        assertEq(pool.totalSupply(tokenId()), depositSize, "pool total supply");
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            collateralValue,
            "pool token balance"
        );
        assertEq(
            IERC20(swapToken).balanceOf(address(users.lp)),
            0,
            "swap token balance"
        );
        assertEq(IERC20(poolToken).balanceOf(users.lp), 0, "lp token balance");
        assertEq(pool.marketPrice(), posKey.upper, "market price");
    }

    function test_swapAndDeposit_Success() public {
        _test_swapAndDeposit_Success(poolKey.isCallPool);
    }

    function _test_swapAndDeposit_RevertIf_NotOperator(bool isCall) internal {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__NotAuthorized.selector);

        posKey.operator = users.trader;

        address swapToken = getSwapToken(isCall);
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            swapToken,
            0,
            0,
            users.lp
        );

        pool.swapAndDeposit(
            swapArgs,
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_swapAndDeposit_RevertIf_NotOperator() public {
        _test_swapAndDeposit_RevertIf_NotOperator(poolKey.isCallPool);
    }

    function _test_swapAndDeposit_RevertIf_InvalidSwapTokenOut(
        bool isCall
    ) internal {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__InvalidSwapTokenOut.selector);

        address swapToken = getSwapToken(isCall);
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            swapToken,
            0,
            0,
            users.lp
        );

        pool.swapAndDeposit(
            swapArgs,
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_swapAndDeposit_RevertIf_InvalidSwapTokenOut() public {
        _test_swapAndDeposit_RevertIf_InvalidSwapTokenOut(poolKey.isCallPool);
    }
}
