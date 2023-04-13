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

abstract contract PoolDepositTest is DeployTest {
    function _test_deposit_1000LC(bool isCall) internal {
        poolKey.isCallPool = isCall;

        IERC20 token = IERC20(getPoolToken(isCall));
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(
            token.balanceOf(users.lp),
            initialCollateral - collateralValue
        );
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_1000_LC() public {
        _test_deposit_1000LC(poolKey.isCallPool);
    }

    function test_deposit_revertIf_SenderNotOperator() public {
        posKey.operator = users.trader;

        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__NotAuthorized.selector);

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function _test_deposit_revertIf_MarketPriceOutOfMinMax(
        bool isCall
    ) internal {
        poolKey.isCallPool = isCall;
        deposit(1000 ether);
        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            posKey.upper + UD60x18.wrap(1),
            posKey.upper,
            Permit2.emptyPermit()
        );

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            posKey.upper - UD60x18.wrap(10),
            posKey.upper - UD60x18.wrap(1),
            Permit2.emptyPermit()
        );
    }

    function test_deposit_revertIf_MarketPriceOutOfMinMax() public {
        _test_deposit_revertIf_MarketPriceOutOfMinMax(poolKey.isCallPool);
    }

    function test_deposit_revertIf_ZeroSize() public {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            ZERO,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_revertIf_Expired() public {
        vm.prank(users.lp);

        vm.warp(poolKey.maturity + 1);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_revertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = UD60x18.wrap(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(1.01e18);
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_revertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = UD60x18.wrap(0.2501e18);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(0.7501e18);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

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
