// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

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

abstract contract PoolSettlePositionTest is DeployTest {
    function _test_settlePosition_trade_Buy100Options()
        internal
        returns (TradeInternal memory trade)
    {
        posKey.orderType = Position.OrderType.CS;

        trade.initialCollateral = deposit(1000 ether);
        trade.size = ud(100 ether);
        (trade.totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            trade.size,
            true
        );

        trade.poolToken = getPoolToken();
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

    function _test_settlePosition_Buy100Options(bool isITM) internal {
        TradeInternal memory trade = _test_settlePosition_trade_Buy100Options();

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        vm.prank(posKey.operator);

        pool.settlePosition(posKey);

        UD60x18 payoff = getExerciseValue(isITM, ONE, settlementPrice);
        uint256 collateral = scaleDecimals(trade.size * payoff);

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), 0);

        assertEq(IERC20(trade.poolToken).balanceOf(address(pool)), collateral);

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey.operator),
            trade.initialCollateral +
                trade.totalPremium -
                collateral -
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

    function test_settlePosition_Buy100Options_ITM() public {
        _test_settlePosition_Buy100Options(true);
    }

    function test_settlePosition_Buy100Options_OTM() public {
        _test_settlePosition_Buy100Options(false);
    }

    function test_settlePosition_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        vm.prank(posKey.operator);
        pool.settlePosition(posKey);
    }

    function test_settlePosition_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OperatorNotAuthorized.selector,
                users.trader
            )
        );
        vm.prank(users.trader);
        pool.settlePosition(posKey);
    }

    function _test_settlePositionFor_Buy100Options(bool isITM) internal {
        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setQuote(settlementPrice.inv());
        oracleAdapter.setQuoteFrom(settlementPrice);

        Position.Key memory posKey2 = Position.Key({
            owner: users.otherLP,
            operator: users.otherLP,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: Position.OrderType.CS
        });

        handleExerciseSettleAuthorization(posKey.operator, 0.1 ether);
        handleExerciseSettleAuthorization(posKey2.operator, 0.1 ether);

        TradeInternal memory trade = _test_settlePosition_trade_Buy100Options();

        vm.startPrank(posKey.operator);

        pool.transferPosition(
            posKey,
            users.otherLP,
            users.otherLP,
            ud(pool.balanceOf(posKey.operator, tokenId()) / 2)
        );

        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();

        uint256 cost = scaleDecimals(ud(0.1 ether));

        vm.warp(poolKey.maturity);
        vm.prank(users.agent);

        Position.Key[] memory p = new Position.Key[](2);
        p[0] = posKey;
        p[1] = posKey2;

        pool.settlePositionFor(p, cost);

        UD60x18 payoff = getExerciseValue(isITM, ONE, settlementPrice);
        uint256 collateral = scaleDecimals((trade.size / TWO) * payoff);

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), 0);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            collateral * 2
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.agent), cost * 2);

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey.operator),
            (trade.initialCollateral / 2) +
                (trade.totalPremium / 2) -
                collateral -
                (protocolFees / 2) -
                cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey2.operator),
            (trade.initialCollateral / 2) +
                (trade.totalPremium / 2) -
                collateral -
                (protocolFees / 2) -
                cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(posKey2), 0);
        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(posKey.operator, tokenId()), 0);

        uint256 tokenId2 = PoolStorage.formatTokenId(
            posKey2.operator,
            posKey2.lower,
            posKey2.upper,
            posKey2.orderType
        );

        assertEq(pool.balanceOf(posKey2.operator, tokenId2), 0);
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), trade.size);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), 0);
    }

    function test_settlePositionFor_Buy100Options_ITM() public {
        _test_settlePositionFor_Buy100Options(true);
    }

    function test_settlePositionFor_Buy100Options_OTM() public {
        _test_settlePositionFor_Buy100Options(false);
    }

    function test_settlePositionFor_RevertIf_TotalCostExceedsExerciseValue()
        public
    {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_settlePosition_trade_Buy100Options();

        UD60x18 payoff = getExerciseValue(false, ONE, settlementPrice);

        uint256 collateral = trade.initialCollateral +
            trade.totalPremium -
            scaleDecimals(trade.size * payoff) -
            pool.protocolFees();

        uint256 cost = collateral + 1 wei;

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.startPrank(posKey.operator);

        userSettings.setAuthorizedAgents(agents);

        // if !isCall, convert collateral to WETH
        userSettings.setAuthorizedCost(
            isCallTest ? cost : (ud(scaleDecimalsTo(cost)) * quote).unwrap()
        );

        vm.stopPrank();
        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                scaleDecimalsTo(cost),
                scaleDecimalsTo(collateral)
            )
        );

        vm.prank(users.agent);

        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;

        pool.settlePositionFor(p, cost);
    }

    function test_settlePositionFor_RevertIf_AgentNotAuthorized() public {
        vm.expectRevert(IPoolInternal.Pool__AgentNotAuthorized.selector);
        vm.prank(users.agent);
        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;
        pool.settlePositionFor(p, 0);
    }

    function test_settlePositionFor_RevertIf_CostNotAuthorized() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.prank(posKey.operator);
        userSettings.setAuthorizedAgents(agents);

        UD60x18 _cost = ud(0.1 ether);
        uint256 cost = scaleDecimals(_cost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostNotAuthorized.selector,
                (_cost * quote).unwrap(),
                0
            )
        );

        vm.prank(users.agent);

        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;

        pool.settlePositionFor(p, cost);
    }
}
