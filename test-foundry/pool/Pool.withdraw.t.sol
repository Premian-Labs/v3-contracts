// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolWithdrawTest is DeployTest {
    function _test_withdraw_750LC(bool isCall) internal {
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);
        vm.warp(block.timestamp + 60);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(200 ether), isCall),
            isCall
        );

        address poolToken = getPoolToken(isCall);

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue
        );
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue
        );

        UD60x18 withdrawSize = UD60x18.wrap(750 ether);
        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        uint256 withdrawCollateralValue = scaleDecimals(
            contractsToCollateral(withdrawSize * avgPrice, isCall),
            isCall
        );

        vm.prank(users.lp);
        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize - withdrawSize
        );
        assertEq(pool.totalSupply(tokenId()), depositSize - withdrawSize);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue - withdrawCollateralValue
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue + withdrawCollateralValue
        );
    }

    function test_withdraw_750LC() public {
        _test_withdraw_750LC(poolKey.isCallPool);
    }

    function test_withdraw_RevertIf_BeforeEndOfWithdrawalDelay() public {
        deposit(1000 ether);

        vm.warp(block.timestamp + 55);
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__WithdrawalDelayNotElapsed.selector);

        pool.withdraw(posKey, UD60x18.wrap(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_NotOperator() public {
        posKey.operator = users.trader;
        vm.expectRevert(IPoolInternal.Pool__NotAuthorized.selector);
        pool.withdraw(posKey, UD60x18.wrap(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_MarketPriceOutOfMinMax() public {
        deposit(1000 ether);

        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.withdraw(
            posKey,
            THREE,
            posKey.upper + UD60x18.wrap(1),
            posKey.upper
        );

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.withdraw(
            posKey,
            THREE,
            posKey.upper - UD60x18.wrap(10),
            posKey.upper - UD60x18.wrap(1)
        );
    }

    function test_withdraw_RevertIf_ZeroSize() public {
        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.withdraw(posKey, ZERO, ZERO, ONE);
    }

    function test_withdraw_RevertIf_Expired() public {
        vm.startPrank(users.lp);

        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_NonExistingPosition() public {
        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__PositionDoesNotExist.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = UD60x18.wrap(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(1.01e18);
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = UD60x18.wrap(0.2501e18);
        pool.withdraw(posKey, THREE, ZERO, ONE);

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(0.7501e18);
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function _test_withdrawAndSwap_Success(bool isCall) internal {
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);
        vm.warp(block.timestamp + 60);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(200 ether), isCall),
            isCall
        );

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue
        );
        assertEq(IERC20(swapToken).balanceOf(users.lp), 0);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue
        );

        UD60x18 withdrawSize = UD60x18.wrap(750 ether);
        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        uint256 withdrawCollateralValue = scaleDecimals(
            contractsToCollateral(withdrawSize * avgPrice, isCall),
            isCall
        );

        uint256 swapQuote = getSwapQuoteExactInput(
            poolToken,
            swapToken,
            withdrawCollateralValue
        );
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
            poolToken,
            swapToken,
            withdrawCollateralValue,
            swapQuote,
            users.lp
        );

        vm.prank(users.lp);
        pool.withdrawAndSwap(swapArgs, posKey, withdrawSize, ZERO, ONE);

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize - withdrawSize,
            "pos lp"
        );
        assertEq(
            pool.totalSupply(tokenId()),
            depositSize - withdrawSize,
            "totalSupply pos"
        );
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue - withdrawCollateralValue,
            "poolToken pool"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue,
            "poolToken lp"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.lp),
            swapQuote,
            "swapToken lp"
        );
    }

    function test_withdrawAndSwap_Success() public {
        _test_withdrawAndSwap_Success(poolKey.isCallPool);
    }

    function _test_withdrawAndSwap_RevertIf_InvalidSwapTokenIn(
        bool isCall
    ) internal {
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        deposit(depositSize);
        vm.warp(block.timestamp + 60);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        UD60x18 withdrawSize = UD60x18.wrap(750 ether);
        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        uint256 withdrawCollateralValue = scaleDecimals(
            contractsToCollateral(withdrawSize * avgPrice, isCall),
            isCall
        );

        uint256 swapQuote = getSwapQuoteExactInput(
            poolToken,
            swapToken,
            withdrawCollateralValue
        );
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
            swapToken,
            swapToken,
            withdrawCollateralValue,
            swapQuote,
            users.lp
        );

        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__InvalidSwapTokenIn.selector);
        pool.withdrawAndSwap(swapArgs, posKey, withdrawSize, ZERO, ONE);
    }

    function test_withdrawAndSwap_RevertIf_InvalidSwapTokenIn() public {
        _test_withdrawAndSwap_RevertIf_InvalidSwapTokenIn(poolKey.isCallPool);
    }
}
