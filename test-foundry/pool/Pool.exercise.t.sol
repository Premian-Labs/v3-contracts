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

struct TradeInternal {
    address poolToken;
    uint256 initialCollateral;
    uint256 totalPremium;
    uint256 feeReceiverBalance;
    UD60x18 tradeSize;
}

abstract contract PoolExerciseTest is DeployTest {
    function _trade_Buy100Options(
        bool isCall
    ) internal returns (TradeInternal memory trade) {
        posKey.orderType = Position.OrderType.CS;

        trade.initialCollateral = deposit(1000 ether);
        trade.tradeSize = UD60x18.wrap(100 ether);
        (trade.totalPremium, ) = pool.getQuoteAMM(trade.tradeSize, true);

        trade.poolToken = getPoolToken(isCall);
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(
            feeReceiver
        );

        vm.startPrank(users.trader);
        deal(trade.poolToken, users.trader, trade.totalPremium);
        IERC20(trade.poolToken).approve(address(router), trade.totalPremium);

        pool.trade(
            trade.tradeSize,
            true,
            trade.totalPremium + trade.totalPremium / 10,
            Permit2.emptyPermit()
        );
        vm.stopPrank();
    }

    function _test_exercise_Buy100Options(bool isCall, bool isITM) internal {
        TradeInternal memory trade = _trade_Buy100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        pool.exercise(users.trader);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, isITM, trade.tradeSize, settlementPrice),
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

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.SHORT),
            trade.tradeSize
        );
    }

    function test_exercise_Buy100Options_ITM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, true);
    }

    function test_exercise_Buy100Options_OTM() public {
        _test_exercise_Buy100Options(poolKey.isCallPool, false);
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.exercise(users.trader);
    }

    function test_exercise_automatic_Buy100Options_ITM() public {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = handleExerciseSettleAuthorization(
            isCall,
            true,
            0.1 ether
        );

        TradeInternal memory trade = _trade_Buy100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        uint256 txCost = scaleDecimals(UD60x18.wrap(0.09 ether), isCall);
        uint256 fee = scaleDecimals(UD60x18.wrap(0.01 ether), isCall);
        uint256 totalCost = txCost + fee;

        vm.warp(poolKey.maturity);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, true, trade.tradeSize, settlementPrice),
            isCall
        );

        vm.prank(users.agent);
        pool.exercise(users.trader, txCost, fee);

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            exerciseValue - totalCost
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.agent), totalCost);

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

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.SHORT),
            trade.tradeSize
        );
    }

    function test_exercise_automatic_RevertIf_TotalCostExceedsExerciseValue()
        public
    {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = handleExerciseSettleAuthorization(
            isCall,
            false,
            0.1 ether
        );

        _trade_Buy100Options(isCall);

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

    function test_exercise_automatic_RevertIf_UnauthorizedAgent() public {
        vm.expectRevert(IPoolInternal.Pool__UnauthorizedAgent.selector);
        vm.prank(users.agent);
        pool.exercise(users.trader, 0, 0);
    }

    function test_exercise_automatic_RevertIf_UnauthorizedTxCostAndFee()
        public
    {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        UD60x18 quote = isCall ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.prank(users.trader);
        userSettings.setAuthorizedAgents(agents);

        UD60x18 _txCost = UD60x18.wrap(0.09 ether);
        UD60x18 _fee = UD60x18.wrap(0.01 ether);

        uint256 txCost = scaleDecimals(_txCost, isCall);
        uint256 fee = scaleDecimals(_fee, isCall);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__UnauthorizedTxCostAndFee.selector,
                ((_txCost + _fee) * quote).unwrap(),
                0
            )
        );

        vm.prank(users.agent);
        pool.exercise(users.trader, txCost, fee);
    }
}
