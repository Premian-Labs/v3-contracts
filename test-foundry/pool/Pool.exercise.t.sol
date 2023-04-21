// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

import "forge-std/console.sol";

abstract contract PoolExerciseTest is DeployTest {
    function getSettlementPrice(
        bool isCall,
        bool isITM
    ) internal pure returns (UD60x18) {
        if (isCall) {
            return isITM ? UD60x18.wrap(1200 ether) : UD60x18.wrap(800 ether);
        } else {
            return isITM ? UD60x18.wrap(800 ether) : UD60x18.wrap(1200 ether);
        }
    }

    function _test_exercise_Buy100Options_ITM(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;

        uint256 initialCollateral = deposit(1000 ether);
        UD60x18 tradeSize = UD60x18.wrap(100 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, true);

        address poolToken = getPoolToken(isCall);
        uint256 feeReceiverBalance = IERC20(poolToken).balanceOf(feeReceiver);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, true);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        pool.exercise(users.trader);
        vm.stopPrank();

        UD60x18 exerciseValue;

        if (isCall) {
            exerciseValue = tradeSize * (settlementPrice - poolKey.strike);
            exerciseValue = exerciseValue / settlementPrice;
        } else {
            exerciseValue = tradeSize * (poolKey.strike - settlementPrice);
        }

        uint256 _exerciseValue = scaleDecimals(exerciseValue, isCall);

        assertEq(IERC20(poolToken).balanceOf(users.trader), _exerciseValue);

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + totalPremium - _exerciseValue - protocolFees
        );

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver) - feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_exercise_Buy100Options_ITM() public {
        _test_exercise_Buy100Options_ITM(poolKey.isCallPool);
    }

    function _test_exercise_Buy100Options_OTM(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;

        uint256 initialCollateral = deposit(1000 ether);
        UD60x18 tradeSize = UD60x18.wrap(100 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, true);

        address poolToken = getPoolToken(isCall);
        uint256 feeReceiverBalance = IERC20(poolToken).balanceOf(feeReceiver);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        pool.exercise(users.trader);
        vm.stopPrank();

        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + totalPremium - protocolFees
        );

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver) - feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_exercise_Buy100Options_OTM() public {
        _test_exercise_Buy100Options_OTM(poolKey.isCallPool);
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        vm.startPrank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.exercise(users.trader);
    }
}
