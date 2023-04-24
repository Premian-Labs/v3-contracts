// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

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

    function getExerciseValue(
        bool isCall,
        bool isITM,
        UD60x18 tradeSize,
        UD60x18 settlementPrice
    ) internal view returns (uint256) {
        UD60x18 exerciseValue = ZERO;

        if (isITM) {
            if (isCall) {
                exerciseValue = tradeSize * (settlementPrice - poolKey.strike);
                exerciseValue = exerciseValue / settlementPrice;
            } else {
                exerciseValue = tradeSize * (poolKey.strike - settlementPrice);
            }
        }

        return scaleDecimals(exerciseValue, isCall);
    }

    function buy100Options(
        bool isCall
    ) internal returns (address, uint256, uint256, uint256, UD60x18) {
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
        vm.stopPrank();

        return (
            poolToken,
            initialCollateral,
            totalPremium,
            feeReceiverBalance,
            tradeSize
        );
    }

    function _test_exercise_Buy100Options(bool isCall, bool isITM) internal {
        (
            address poolToken,
            uint256 initialCollateral,
            uint256 totalPremium,
            uint256 feeReceiverBalance,
            UD60x18 tradeSize
        ) = buy100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        pool.exercise(users.trader);

        uint256 exerciseValue = getExerciseValue(
            isCall,
            isITM,
            tradeSize,
            settlementPrice
        );

        assertEq(IERC20(poolToken).balanceOf(users.trader), exerciseValue);

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + totalPremium - exerciseValue - protocolFees
        );

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver) - feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_exercise_Buy100Options_ITM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, true);
    }

    function test_exercise_Buy100Options_OTM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, false);
    }

    function test_exercise_automatic_Buy100Options_ITM() public {
        oracleAdapter.setQuote(UD60x18.wrap(1 ether));

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.startPrank(users.trader);
        userSettings.setAuthorizedAgents(agents);
        userSettings.setAuthorizedTxCostAndFee(0.1 ether);
        vm.stopPrank();

        bool isCall = poolKey.isCallPool;

        (
            address poolToken,
            uint256 initialCollateral,
            uint256 totalPremium,
            uint256 feeReceiverBalance,
            UD60x18 tradeSize
        ) = buy100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, true);
        oracleAdapter.setQuoteFrom(settlementPrice);

        uint256 txCost = scaleDecimals(UD60x18.wrap(0.09 ether), isCall);
        uint256 fee = scaleDecimals(UD60x18.wrap(0.01 ether), isCall);
        uint256 totalCost = txCost + fee;

        vm.warp(poolKey.maturity);

        uint256 exerciseValue = getExerciseValue(
            isCall,
            true,
            tradeSize,
            settlementPrice
        );

        vm.prank(users.agent);
        pool.exercise(users.trader, txCost, fee);

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            exerciseValue - totalCost
        );

        assertEq(IERC20(poolToken).balanceOf(users.agent), totalCost);

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialCollateral + totalPremium - exerciseValue - protocolFees
        );

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver) - feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_exercise_automatic_RevertIf_TotalCostExceedsExerciseValue()
        public
    {
        oracleAdapter.setQuote(UD60x18.wrap(1 ether));

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.startPrank(users.trader);
        userSettings.setAuthorizedAgents(agents);
        userSettings.setAuthorizedTxCostAndFee(0.1 ether);
        vm.stopPrank();

        bool isCall = poolKey.isCallPool;
        buy100Options(isCall);

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        oracleAdapter.setQuoteFrom(settlementPrice);

        uint256 txCost = scaleDecimals(UD60x18.wrap(0.09 ether), isCall);
        uint256 fee = scaleDecimals(UD60x18.wrap(0.01 ether), isCall);
        uint256 totalCost = txCost + fee;

        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TotalCostExceedsExerciseValue.selector,
                scaleDecimalsTo(totalCost, isCall),
                0
            )
        );

        vm.prank(users.agent);
        pool.exercise(users.trader, txCost, fee);
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.exercise(users.trader);
    }

    function test_exercise_RevertIf_UnauthorizedAgent() public {
        vm.expectRevert(IPoolInternal.Pool__UnauthorizedAgent.selector);
        vm.prank(users.agent);
        pool.exercise(users.trader, 0, 0);
    }

    function test_exercise_RevertIf_UnauthorizedTxCostAndFee() public {
        oracleAdapter.setQuote(UD60x18.wrap(1 ether));

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.prank(users.trader);
        userSettings.setAuthorizedAgents(agents);

        bool isCall = poolKey.isCallPool;
        uint256 txCost = scaleDecimals(UD60x18.wrap(0.09 ether), isCall);
        uint256 fee = scaleDecimals(UD60x18.wrap(0.01 ether), isCall);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__UnauthorizedTxCostAndFee.selector,
                scaleDecimalsTo(txCost + fee, isCall),
                0
            )
        );

        vm.prank(users.agent);
        pool.exercise(users.trader, txCost, fee);
    }
}
