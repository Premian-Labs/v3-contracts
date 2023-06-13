// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

abstract contract PoolWithdrawTest is DeployTest {
    function test_withdraw_750LC() public {
        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);
        vm.warp(block.timestamp + 60);

        uint256 depositCollateralValue = scaleDecimals(contractsToCollateral(ud(200 ether)));

        address poolToken = getPoolToken();

        assertEq(IERC20(poolToken).balanceOf(users.lp), initialCollateral - depositCollateralValue);
        assertEq(IERC20(poolToken).balanceOf(address(pool)), depositCollateralValue);

        UD60x18 withdrawSize = ud(750 ether);
        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        uint256 withdrawCollateralValue = scaleDecimals(contractsToCollateral(withdrawSize * avgPrice));

        vm.prank(users.lp);
        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize - withdrawSize);
        assertEq(pool.totalSupply(tokenId()), depositSize - withdrawSize);
        assertEq(IERC20(poolToken).balanceOf(address(pool)), depositCollateralValue - withdrawCollateralValue);
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue + withdrawCollateralValue
        );
    }

    function test_withdraw_CS_Straddle() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);

        uint256 depositSize = 1 ether;
        uint256 withdrawSize = 0.75 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, true, depositSize, false);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), 0 ether);
        vm.warp(block.timestamp + 60);
        assertEq(pool.marketPrice(), 0.125 ether);
        assertEq(pool.getCurrentTick(), 0.1 ether);
        vm.startPrank(users.lp);
        pool.withdraw(posKey, ud(withdrawSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.totalSupply(tokenId()), ud(0.25 ether));
        assertEq(pool.getCurrentTick(), 0.1 ether);
        assertEq(pool.getLiquidityRate(), 0.0025 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 0.0025 ether);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(0.0 ether));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.1875 ether));
        // balance should equal
        // premiums generated = (0.125^2 - 0.1^2) / (2 * (0.1)) * 0.75 = 0.02109375
        // collateral removed = 0.75 * collateral remaining = 0.75 * 0.75 = 0.5625
        // new balance = 0.5625 + 0.02109375 = 0.58359375
        uint256 expectedBalance = isCallTest
            ? scaleDecimals(ud(0.58359375 ether))
            : scaleDecimals(ud(0.58359375 ether) * poolKey.strike);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), expectedBalance);
    }

    function test_withdraw_CSUP_Straddle() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);

        uint256 depositSize = 1 ether;
        uint256 withdrawSize = 0.75 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, true, depositSize, true);
        uint256 expectedBalanceAfterDeposit = isCallTest
            ? scaleDecimals(ud(0.15 ether))
            : scaleDecimals(ud(0.15 ether) * poolKey.strike);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), expectedBalanceAfterDeposit);
        vm.warp(block.timestamp + 60);
        assertEq(pool.marketPrice(), 0.125 ether);
        assertEq(pool.getCurrentTick(), 0.1 ether);
        vm.startPrank(users.lp);
        pool.withdraw(posKey, ud(withdrawSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.totalSupply(tokenId()), ud(0.25 ether));
        assertEq(pool.getCurrentTick(), 0.1 ether);
        assertEq(pool.getLiquidityRate(), 0.0025 ether);
        assertEq(pool.getLongRate(), 0.0 ether);
        assertEq(pool.getShortRate(), 0.0025 ether);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(0.0 ether));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.1875 ether));
        // balance should equal
        // balance after deposit = 0.15
        // premiums generated = (0.125^2 - 0.1^2) / (2 * (0.1)) = 0.028125
        // collateral in position = 0.75  - 0.15 + 0.028125 = 0.628125
        // new balance = 0.15 + 0.75 * 0.628125 = 0.62109375
        uint256 expectedBalance = isCallTest
            ? scaleDecimals(ud(0.62109375 ether))
            : scaleDecimals(ud(0.62109375 ether) * poolKey.strike);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), expectedBalance);
    }

    function test_withdraw_LC_Straddle() public {
        posKey.lower = ud(0.1 ether);
        posKey.upper = ud(0.2 ether);
        posKey.orderType = Position.OrderType.LC;
        uint256 depositSize = 1 ether;
        uint256 withdrawSize = 0.75 ether;
        uint256 tradeSize = 0.25 ether;
        trade(tradeSize, false, depositSize);
        uint256 expectedBalanceAfterDeposit = isCallTest
            ? scaleDecimals(ud(0.85 ether))
            : scaleDecimals(ud(0.85 ether) * poolKey.strike);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), expectedBalanceAfterDeposit);
        vm.warp(block.timestamp + 60);
        assertEq(pool.marketPrice(), 0.175 ether);
        assertEq(pool.getCurrentTick(), 0.1 ether);
        vm.startPrank(users.lp);
        pool.withdraw(posKey, ud(withdrawSize), ZERO, ONE);
        vm.stopPrank();
        assertEq(pool.totalSupply(tokenId()), ud(0.25 ether));
        assertEq(pool.getCurrentTick(), 0.1 ether);
        assertEq(pool.getLiquidityRate(), 0.0025 ether);
        assertEq(pool.getLongRate(), 0.0025 ether);
        assertEq(pool.getShortRate(), 0.0 ether);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), ud(0.1875 ether));
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), ud(0.0 ether));
        // balance should equal
        // balance after deposit = 0.85
        // collateral in position = (0.175^2 - 0.1^2) / (2 * (0.1)) = 0.103125
        // new balance = 0.85 + 0.75 * 0.103125 = 0.92734375
        uint256 expectedBalance = isCallTest
            ? scaleDecimals(ud(0.92734375 ether))
            : scaleDecimals(ud(0.92734375 ether) * poolKey.strike);
        assertEq(IERC20(getPoolToken()).balanceOf(users.lp), expectedBalance);
    }

    function test_withdraw_RevertIf_BeforeEndOfWithdrawalDelay() public {
        deposit(1000 ether);

        vm.warp(block.timestamp + 55);
        vm.prank(users.lp);
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__WithdrawalDelayNotElapsed.selector, block.timestamp + 5)
        );

        pool.withdraw(posKey, ud(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_OperatorNotAuthorized() public {
        posKey.operator = users.trader;
        vm.prank(users.lp);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.lp));
        pool.withdraw(posKey, ud(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_MarketPriceOutOfMinMax() public {
        deposit(1000 ether);

        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        UD60x18 minPrice = posKey.upper + ud(1);
        UD60x18 maxPrice = posKey.upper;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.withdraw(posKey, THREE, minPrice, maxPrice);

        minPrice = posKey.upper - ud(10);
        maxPrice = posKey.upper - ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.withdraw(posKey, THREE, minPrice, maxPrice);
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

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__PositionDoesNotExist.selector, posKey.owner, tokenId())
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = ud(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(1.01e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ud(0.2501e18);
        posKey.upper = ud(0.7501e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__TickWidthInvalid.selector, posKey.lower));
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(0.7501e18);
        // we won't catch the second tickWidth revert as there is no way to define a valid lower and an invalid upper
        // without having an invalid range
        vm.expectRevert();
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidSize() public {
        uint256 size = 1 ether + 1;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, size));
        vm.startPrank(users.lp);
        pool.withdraw(posKey, ud(size), ZERO, ONE);
        vm.stopPrank();
        size = 1 ether + 199;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidSize.selector, size));
        vm.startPrank(users.lp);
        pool.withdraw(posKey, ud(size), ZERO, ONE);
        vm.stopPrank();
        // this one below is expected to pass as the range order has a width of 200 ticks
        size = 1 ether + 400;
        deposit(size);
        vm.warp(block.timestamp + 60);
        vm.startPrank(users.lp);
        size = 1 ether + 200;
        pool.withdraw(posKey, ud(size), ZERO, ONE);
        vm.stopPrank();
    }
}
