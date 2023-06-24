// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

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

abstract contract PoolSettlePositionTest is DeployTest {
    function _test_settlePosition_trade_Buy100Options() internal returns (TradeInternal memory trade) {
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
            trade.initialCollateral + trade.totalPremium - collateral - protocolFees
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

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
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.trader));
        vm.prank(users.trader);
        pool.settlePosition(posKey);
    }

    function _test_settlePositionFor_Buy100Options(bool isITM) internal {
        UD60x18 settlementPrice = getSettlementPrice(isITM);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        Position.Key memory posKey2 = Position.Key({
            owner: users.otherLP,
            operator: users.otherLP,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: Position.OrderType.CS
        });

        UD60x18 authorizedCost = ud(0.1e18);
        enableExerciseSettleAuthorization(posKey.operator, authorizedCost);
        enableExerciseSettleAuthorization(posKey2.operator, authorizedCost);

        TradeInternal memory trade = _test_settlePosition_trade_Buy100Options();

        vm.startPrank(posKey.operator);
        pool.transferPosition(posKey, users.otherLP, users.otherLP, ud(pool.balanceOf(posKey.operator, tokenId()) / 2));
        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();
        vm.warp(poolKey.maturity);

        Position.Key[] memory p = new Position.Key[](2);
        p[0] = posKey;
        p[1] = posKey2;

        uint256 cost = scaleDecimals(authorizedCost);
        vm.prank(users.operator);
        pool.settlePositionFor(p, cost);

        UD60x18 payoff = getExerciseValue(isITM, ONE, settlementPrice);
        uint256 collateral = scaleDecimals((trade.size / TWO) * payoff);

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), 0);
        assertEq(IERC20(trade.poolToken).balanceOf(address(pool)), collateral * 2);
        assertEq(IERC20(trade.poolToken).balanceOf(users.operator), cost * 2);

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey.operator),
            (trade.initialCollateral / 2) + (trade.totalPremium / 2) - collateral - (protocolFees / 2) - cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(posKey2.operator),
            (trade.initialCollateral / 2) + (trade.totalPremium / 2) - collateral - (protocolFees / 2) - cost
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(posKey2), 0);
        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(posKey.operator, tokenId()), 0);

        uint256 tokenId2 = PoolStorage.formatTokenId(posKey2.operator, posKey2.lower, posKey2.upper, posKey2.orderType);

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

    function test_settlePositionFor_RevertIf_TotalCostExceedsExerciseValue() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_settlePosition_trade_Buy100Options();

        UD60x18 payoff = getExerciseValue(false, ONE, settlementPrice);
        UD60x18 collateral = scaleDecimals(
            trade.initialCollateral + trade.totalPremium - scaleDecimals(trade.size * payoff) - pool.protocolFees()
        );

        UD60x18 cost = collateral + ONE;
        enableExerciseSettleAuthorization(posKey.operator, isCallTest ? cost : cost * quote);

        vm.warp(poolKey.maturity);

        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;

        uint256 _cost = scaleDecimals(cost);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__CostExceedsPayout.selector, cost, collateral));
        vm.prank(users.operator);
        pool.settlePositionFor(p, _cost);
    }

    function test_settlePositionFor_RevertIf_ActionNotAuthorized() public {
        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__ActionNotAuthorized.selector,
                posKey.operator,
                users.operator,
                IUserSettings.Action.SETTLE_POSITION
            )
        );

        vm.prank(users.operator);
        pool.settlePositionFor(p, 0);
    }

    function test_settlePositionFor_RevertIf_CostNotAuthorized() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        setActionAuthorization(posKey.operator, IUserSettings.Action.SETTLE_POSITION, true);
        UD60x18 cost = ud(0.1e18);

        Position.Key[] memory p = new Position.Key[](1);
        p[0] = posKey;

        uint256 _cost = scaleDecimals(cost);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__CostNotAuthorized.selector, cost * quote, ZERO));
        vm.prank(users.operator);
        pool.settlePositionFor(p, _cost);
    }

    function test_settlePositionFor_RevertIf_CostNotCovered() public {
        // This test is a PoC for an issue discovered in the audit which is now fixed

        UD60x18 poolValue = ud(1000 ether);
        // as an LP, deposit ether into a pool
        // deposit is a helper function that handles this for us
        deposit(poolValue);

        // an attacker sees the liquidity in the pool, and using two addresses will
        // conspire to drain the pool of its liquidity
        address user = vm.addr(10);
        address operator = vm.addr(11);

        IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
        actions[0] = IUserSettings.Action.SETTLE_POSITION;

        bool[] memory authorization = new bool[](1);
        authorization[0] = true;

        // attackerUser sets attackerAgent as their operator, and assigns a cost of
        // the entire pool value
        vm.startPrank(user);

        userSettings.setActionAuthorization(operator, actions, authorization);
        userSettings.setAuthorizedCost(poolValue);

        vm.stopPrank();

        // create an erroneous position that will be used to 'settle' and steal all
        // the tokens out of the pool
        Position.Key memory fakePosition1 = Position.Key({
            owner: user,
            operator: operator,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: Position.OrderType.LC
        });

        address poolToken = getPoolToken();

        // take a snapshot of various balances before the attack
        uint256 originalPoolBalance = IERC20(poolToken).balanceOf(address(pool));

        // Skip ahead in time to when the positions have matured
        vm.warp(poolKey.maturity);

        // This is the key to the attack. We need to trick the pool into generating an invalid tokenId. To do this, we
        // update one of the fields used to generate the tokenId to values that do not correspond to exisitng postiions.
        fakePosition1.lower = ud(.7e18);

        // settlePositionFor batches handling position settlements, so we need to provide an array
        Position.Key[] memory p = new Position.Key[](1);
        p[0] = fakePosition1;

        // Verify that the pool contains tokens (so we can steal them)
        assertGt(originalPoolBalance, 0);

        // Set the cost ("settlement fee") equal to the current balance of the pool
        uint256 cost = originalPoolBalance;

        // This call will short-circuit before closing the position due to the invalid `lower` values
        // set above, but it will still pay the operator their fee (all the tokens in the pool)
        vm.prank(operator);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                isCallTest ? ud(200e18) : ud(200_000e18),
                ZERO
            )
        );

        pool.settlePositionFor(p, cost);
    }
}
