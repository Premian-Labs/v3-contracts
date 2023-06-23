// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ONE, TWO} from "contracts/libraries/Constants.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

struct TradeInternal {
    address poolToken;
    uint256 initialCollateral;
    uint256 traderCollateral;
    uint256 totalPremium;
    uint256 feeReceiverBalance;
    UD60x18 size;
}

abstract contract PoolSettleTest is DeployTest {
    function _test_settle_trade_Sell100Options() internal returns (TradeInternal memory trade) {
        UD60x18 depositSize = ud(1000 ether);
        deposit(depositSize);

        trade.initialCollateral = scaleDecimals(contractsToCollateral(depositSize) * posKey.lower.avg(posKey.upper));

        trade.size = ud(100 ether);

        trade.traderCollateral = scaleDecimals(contractsToCollateral(trade.size));

        (trade.totalPremium, ) = pool.getQuoteAMM(users.trader, trade.size, false);

        trade.poolToken = getPoolToken();
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(feeReceiver);

        vm.startPrank(users.trader);

        deal(trade.poolToken, users.trader, trade.traderCollateral);
        IERC20(trade.poolToken).approve(address(router), trade.traderCollateral);

        pool.trade(trade.size, false, trade.totalPremium - trade.totalPremium / 10, address(0));

        vm.stopPrank();
    }

    function _test_settle_Sell100Options(bool isITM) internal {
        TradeInternal memory trade = _test_settle_trade_Sell100Options();

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);
        vm.prank(users.trader);
        pool.settle();

        uint256 exerciseValue = scaleDecimals(getExerciseValue(isITM, trade.size, settlementPrice));

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            trade.traderCollateral + trade.totalPremium - exerciseValue
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + exerciseValue - trade.totalPremium - protocolFees
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), trade.size);
    }

    function test_settle_Sell100Options_ITM() public {
        _test_settle_Sell100Options(true);
    }

    function test_settle_Sell100Options_OTM() public {
        _test_settle_Sell100Options(false);
    }

    function test_settle_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        vm.prank(users.trader);
        pool.settle();
    }

    function _test_settleFor_Sell100Options(bool isITM) internal {
        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setQuote(settlementPrice.inv());
        oracleAdapter.setQuoteFrom(settlementPrice);

        enableExerciseSettleAuthorization(users.trader, 0.1 ether);
        enableExerciseSettleAuthorization(users.otherTrader, 0.1 ether);

        TradeInternal memory trade = _test_settle_trade_Sell100Options();

        vm.startPrank(users.trader);

        pool.setApprovalForAll(users.otherTrader, true);

        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.SHORT, (trade.size / TWO).unwrap(), "");

        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();

        uint256 cost = scaleDecimals(ud(0.1 ether));

        vm.warp(poolKey.maturity);
        vm.prank(users.operator);

        address[] memory holders = new address[](2);
        holders[0] = users.trader;
        holders[1] = users.otherTrader;

        pool.settleFor(holders, cost);

        uint256 exerciseValue = scaleDecimals(getExerciseValue(isITM, trade.size / TWO, settlementPrice));

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            (trade.traderCollateral / 2) + trade.totalPremium - exerciseValue - cost
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.otherTrader),
            (trade.traderCollateral / 2) - exerciseValue - cost
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.operator), (cost * 2));

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + (exerciseValue * 2) - trade.totalPremium - protocolFees
        );

        assertEq(IERC20(trade.poolToken).balanceOf(feeReceiver) - trade.feeReceiverBalance, protocolFees);

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), trade.size);
    }

    function test_settleFor_Sell100Options_ITM() public {
        _test_settleFor_Sell100Options(true);
    }

    function test_settleFor_Sell100Options_OTM() public {
        _test_settleFor_Sell100Options(false);
    }

    function test_settleFor_RevertIf_TotalCostExceedsCollateralValue() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_settle_trade_Sell100Options();

        UD60x18 exerciseValue = getExerciseValue(false, trade.size, settlementPrice);
        UD60x18 collateral = getCollateralValue(trade.size, exerciseValue);
        uint256 cost = collateral.unwrap() + 1 wei;

        setAuthorizations(users.trader, IUserSettings.Authorization.SETTLE, true);

        {
            // if !isCall, convert collateral to WETH
            uint256 _cost = isCallTest ? cost : (ud(scaleDecimalsTo(cost)) * quote).unwrap();
            vm.prank(users.trader);
            userSettings.setAuthorizedCost(_cost);
        }

        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                scaleDecimalsTo(cost),
                collateral.unwrap()
            )
        );

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        vm.prank(users.operator);
        pool.settleFor(holders, cost);
    }

    function test_settleFor_RevertIf_OperatorNotAuthorized() public {
        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        vm.prank(users.operator);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.operator));
        pool.settleFor(holders, 0);
    }

    function test_settleFor_RevertIf_CostNotAuthorized() public {
        UD60x18 settlementPrice = getSettlementPrice(false);
        UD60x18 quote = isCallTest ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);

        setAuthorizations(users.trader, IUserSettings.Authorization.SETTLE, true);

        UD60x18 _cost = ud(0.1 ether);
        uint256 cost = scaleDecimals(_cost);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__CostNotAuthorized.selector, (_cost * quote).unwrap(), 0)
        );

        vm.prank(users.operator);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        pool.settleFor(holders, cost);
    }

    function test_getSettlementPrice_ReturnExpectedValue() public {
        assertEq(pool.getSettlementPrice(), 0);

        bool isITM = true;
        UD60x18 _settlementPrice = getSettlementPrice(isITM);
        _test_settle_Sell100Options(isITM);
        assertEq(pool.getSettlementPrice(), _settlementPrice);
    }
}
