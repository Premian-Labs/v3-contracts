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
    UD60x18 size;
}

abstract contract PoolSettlePositionTest is DeployTest {
    function _test_settle_position_trade_Buy100Options(
        bool isCall
    ) internal returns (TradeInternal memory trade) {
        posKey.orderType = Position.OrderType.CS;

        trade.initialCollateral = deposit(1000 ether);
        trade.size = UD60x18.wrap(100 ether);
        (trade.totalPremium, ) = pool.getQuoteAMM(trade.size, true);

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
            Permit2.emptyPermit()
        );

        vm.stopPrank();
    }

    function _test_settle_position_Buy100Options(
        bool isCall,
        bool isITM
    ) internal {
        TradeInternal memory trade = _test_settle_position_trade_Buy100Options(
            isCall
        );

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);

        pool.settlePosition(posKey);

        UD60x18 payoff = getExerciseValue(isCall, isITM, ONE, settlementPrice);
        uint256 exerciseValue = scaleDecimals(trade.size * payoff, isCall);

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), 0);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            exerciseValue
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey.operator),
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

        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(posKey.operator, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), trade.size);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), 0);
    }

    function test_settle_position_Buy100Options_ITM() public {
        _test_settle_position_Buy100Options(poolKey.isCallPool, true);
    }

    function test_settle_position_Buy100Options_OTM() public {
        _test_settle_position_Buy100Options(poolKey.isCallPool, false);
    }

    function test_settle_position_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.settlePosition(posKey);
    }

    function _test_settle_position_automatic_Buy100Options(
        bool isCall,
        bool isITM
    ) internal {
        UD60x18 settlementPrice = handleExerciseSettleAuthorization(
            isCall,
            isITM,
            posKey.operator,
            0.1 ether
        );

        TradeInternal memory trade = _test_settle_position_trade_Buy100Options(
            isCall
        );

        uint256 protocolFees = pool.protocolFees();

        uint256 cost = scaleDecimals(UD60x18.wrap(0.1 ether), isCall);

        vm.warp(poolKey.maturity);
        vm.prank(users.agent);

        pool.settlePosition(posKey, cost);

        UD60x18 payoff = getExerciseValue(isCall, isITM, ONE, settlementPrice);
        uint256 exerciseValue = scaleDecimals(trade.size * payoff, isCall);

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), 0);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            exerciseValue
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.agent), cost);

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey.operator),
            trade.initialCollateral +
                trade.totalPremium -
                exerciseValue -
                protocolFees -
                cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(posKey.operator, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), trade.size);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), 0);
    }

    function test_settle_position_automatic_Buy100Options_ITM() public {
        _test_settle_position_automatic_Buy100Options(poolKey.isCallPool, true);
    }

    function test_settle_position_automatic_Buy100Options_OTM() public {
        _test_settle_position_automatic_Buy100Options(
            poolKey.isCallPool,
            false
        );
    }

    function test_settle_position_automatic_RevertIf_TotalCostExceedsExerciseValue()
        public
    {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        UD60x18 quote = isCall ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_settle_position_trade_Buy100Options(
            isCall
        );

        UD60x18 payoff = getExerciseValue(isCall, false, ONE, settlementPrice);

        uint256 collateral = trade.initialCollateral +
            trade.totalPremium -
            scaleDecimals(trade.size * payoff, isCall) -
            pool.protocolFees();

        uint256 cost = collateral + 1 wei;

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.startPrank(posKey.operator);

        userSettings.setAuthorizedAgents(agents);

        // if !isCall, convert collateral to WETH
        userSettings.setAuthorizedCost(
            isCall
                ? cost
                : (UD60x18.wrap(scaleDecimalsTo(cost, isCall)) * quote).unwrap()
        );

        vm.stopPrank();

        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                scaleDecimalsTo(cost, isCall),
                scaleDecimalsTo(collateral, isCall)
            )
        );

        vm.prank(users.agent);
        pool.settlePosition(posKey, cost);
    }

    function test_settle_position_automatic_RevertIf_UnauthorizedAgent()
        public
    {
        vm.expectRevert(IPoolInternal.Pool__UnauthorizedAgent.selector);
        vm.prank(users.agent);
        pool.settlePosition(posKey, 0);
    }

    function test_settle_position_automatic_RevertIf_UnauthorizedTxCostAndFee()
        public
    {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        UD60x18 quote = isCall ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.prank(posKey.operator);
        userSettings.setAuthorizedAgents(agents);

        UD60x18 _cost = UD60x18.wrap(0.1 ether);
        uint256 cost = scaleDecimals(_cost, isCall);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__UnauthorizedCost.selector,
                (_cost * quote).unwrap(),
                0
            )
        );

        vm.prank(users.agent);
        pool.settlePosition(posKey, cost);
    }
}
