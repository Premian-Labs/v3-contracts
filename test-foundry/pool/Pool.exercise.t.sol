// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

struct TradeInternal {
    address poolToken;
    uint256 initialCollateral;
    uint256 totalPremium;
    uint256 feeReceiverBalance;
    UD60x18 size;
}

abstract contract PoolExerciseTest is DeployTest {
    function _test_exercise_trade_Buy100Options(
        bool isCall
    ) internal returns (TradeInternal memory trade) {
        posKey.orderType = Position.OrderType.CS;

        trade.initialCollateral = deposit(1000 ether);
        trade.size = ud(100 ether);
        (trade.totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            trade.size,
            true
        );

        trade.poolToken = getPoolToken(isCall);
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(
            feeReceiver
        );

        vm.startPrank(users.trader);

        deal(trade.poolToken, users.trader, trade.totalPremium);
        IERC20(trade.poolToken).approve(address(router), trade.totalPremium);

        pool.trade(
            trade.size,
            true,
            trade.totalPremium + trade.totalPremium / 10,
            address(0)
        );

        vm.stopPrank();
    }

    function _test_exercise_Buy100Options(bool isCall, bool isITM) internal {
        TradeInternal memory trade = _test_exercise_trade_Buy100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        vm.prank(users.trader);
        pool.exercise();

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, isITM, trade.size, settlementPrice),
            isCall
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            exerciseValue
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral +
                trade.totalPremium -
                exerciseValue -
                protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), trade.size);
    }

    function test_exercise_Buy100Options_ITM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, true);
    }

    function test_exercise_Buy100Options_OTM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, false);
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.exercise();
    }

    function test_exerciseFor_Buy100Options_ITM() public {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, true);
        oracleAdapter.setQuote(settlementPrice.inv());
        oracleAdapter.setQuoteFrom(settlementPrice);

        handleExerciseSettleAuthorization(users.trader, 0.1 ether);
        handleExerciseSettleAuthorization(users.otherTrader, 0.1 ether);

        TradeInternal memory trade = _test_exercise_trade_Buy100Options(isCall);

        vm.startPrank(users.trader);

        pool.setApprovalForAll(users.otherTrader, true);

        pool.safeTransferFrom(
            users.trader,
            users.otherTrader,
            PoolStorage.LONG,
            (trade.size / TWO).unwrap(),
            ""
        );

        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();
        uint256 cost = scaleDecimals(ud(0.1 ether), isCall);

        vm.warp(poolKey.maturity);
        vm.prank(users.agent);

        address[] memory holders = new address[](2);
        holders[0] = users.trader;
        holders[1] = users.otherTrader;

        pool.exerciseFor(holders, cost);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, true, trade.size / TWO, settlementPrice),
            isCall
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            exerciseValue - cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.otherTrader),
            exerciseValue - cost
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.agent), (cost * 2));

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral +
                trade.totalPremium -
                (exerciseValue * 2) -
                protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), trade.size);
    }

    function test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue() public {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        oracleAdapter.setQuote(settlementPrice.inv());
        oracleAdapter.setQuoteFrom(settlementPrice);

        handleExerciseSettleAuthorization(users.trader, 0.1 ether);

        _test_exercise_trade_Buy100Options(isCall);

        uint256 cost = scaleDecimals(ud(0.1 ether), isCall);

        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                scaleDecimalsTo(cost, isCall),
                0
            )
        );

        vm.prank(users.agent);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        pool.exerciseFor(holders, cost);
    }

    function test_exerciseFor_RevertIf_AgentNotAuthorized() public {
        vm.expectRevert(IPoolInternal.Pool__AgentNotAuthorized.selector);
        vm.prank(users.agent);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        pool.exerciseFor(holders, 0);
    }

    function test_exerciseFor_RevertIf_CostNotAuthorized() public {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        UD60x18 quote = isCall ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.prank(users.trader);
        userSettings.setAuthorizedAgents(agents);

        UD60x18 _cost = ud(0.1 ether);
        uint256 cost = scaleDecimals(_cost, isCall);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostNotAuthorized.selector,
                (_cost * quote).unwrap(),
                0
            )
        );

        vm.prank(users.agent);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        pool.exerciseFor(holders, cost);
    }
}
