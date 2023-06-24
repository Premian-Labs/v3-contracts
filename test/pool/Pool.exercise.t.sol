// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

struct TradeInternal {
    address poolToken;
    uint256 initialCollateral;
    uint256 totalPremium;
    uint256 feeReceiverBalance;
    UD60x18 size;
}

abstract contract PoolExerciseTest is DeployTest {
    function _test_exercise_trade_Buy100Options() internal returns (TradeInternal memory trade) {
        posKey.orderType = Position.OrderType.CS;

        trade.initialCollateral = deposit(1000 ether);
        trade.size = ud(100 ether);
        (trade.totalPremium, ) = pool.getQuoteAMM(users.trader, trade.size, true);

        trade.poolToken = getPoolToken();
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(feeReceiver);

        vm.startPrank(users.trader);

        deal(trade.poolToken, users.trader, trade.totalPremium);
        IERC20(trade.poolToken).approve(address(router), trade.totalPremium);

        pool.trade(trade.size, true, trade.totalPremium + trade.totalPremium / 10, address(0));

        vm.stopPrank();
    }

    function _test_exercise_Buy100Options(bool isITM) internal {
        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        vm.prank(users.trader);
        pool.exercise();

        uint256 exerciseValue = scaleDecimals(getExerciseValue(isITM, trade.size, settlementPrice));

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), exerciseValue);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + trade.totalPremium - exerciseValue - protocolFees
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), trade.size);
    }

    function test_exercise_Buy100Options_ITM() public {
        _test_exercise_Buy100Options(true);
    }

    function test_exercise_Buy100Options_OTM() public {
        _test_exercise_Buy100Options(false);
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.exercise();
    }

    function test_exerciseFor_Buy100Options_ITM() public {
        UD60x18 settlementPrice = getSettlementPrice(true);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        UD60x18 authorizedCost = ud(0.1e18);
        enableExerciseSettleAuthorization(users.trader, authorizedCost);
        enableExerciseSettleAuthorization(users.otherTrader, authorizedCost);

        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        vm.startPrank(users.trader);
        pool.setApprovalForAll(users.otherTrader, true);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, (trade.size / TWO).unwrap(), "");
        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();
        vm.warp(poolKey.maturity);

        address[] memory holders = new address[](2);
        holders[0] = users.trader;
        holders[1] = users.otherTrader;

        uint256 cost = scaleDecimals(authorizedCost);

        vm.prank(users.operator);
        pool.exerciseFor(holders, cost);

        uint256 exerciseValue = scaleDecimals(getExerciseValue(true, trade.size / TWO, settlementPrice));

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), exerciseValue - cost);
        assertEq(IERC20(trade.poolToken).balanceOf(users.otherTrader), exerciseValue - cost);

        assertEq(IERC20(trade.poolToken).balanceOf(users.operator), (cost * 2));

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + trade.totalPremium - (exerciseValue * 2) - protocolFees
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), trade.size);
    }

    function test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue_OTM() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        _test_exercise_trade_Buy100Options();

        UD60x18 cost = ONE; // exercise value is zero
        UD60x18 authorizedCost = isCallTest ? cost : cost * quote;

        enableExerciseSettleAuthorization(users.trader, authorizedCost);
        vm.warp(poolKey.maturity);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        uint256 _cost = scaleDecimals(cost);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__CostExceedsPayout.selector, cost, ZERO));
        vm.prank(users.operator);
        pool.exerciseFor(holders, _cost);
    }

    function test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue_ITM() public {
        UD60x18 settlementPrice = getSettlementPrice(true);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        UD60x18 exerciseValue = getExerciseValue(true, trade.size, settlementPrice);
        UD60x18 cost = exerciseValue + ONE;
        UD60x18 authorizedCost = isCallTest ? cost : cost * quote;

        enableExerciseSettleAuthorization(users.trader, authorizedCost);
        vm.warp(poolKey.maturity);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        uint256 _cost = scaleDecimals(cost);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__CostExceedsPayout.selector, cost, exerciseValue));
        vm.prank(users.operator);
        pool.exerciseFor(holders, _cost);
    }

    function test_exerciseFor_RevertIf_ActionNotAuthorized() public {
        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__ActionNotAuthorized.selector,
                users.trader,
                users.operator,
                IUserSettings.Action.Exercise
            )
        );

        vm.prank(users.operator);
        pool.exerciseFor(holders, 0);
    }

    function test_exerciseFor_RevertIf_CostNotAuthorized() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        setActionAuthorization(users.trader, IUserSettings.Action.Exercise, true);
        UD60x18 authorizedCost = ud(0.1e18);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        uint256 cost = scaleDecimals(authorizedCost);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__CostNotAuthorized.selector, authorizedCost * quote, ZERO)
        );

        vm.prank(users.operator);
        pool.exerciseFor(holders, cost);
    }
}
