// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

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
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(FEE_RECEIVER);

        vm.startPrank(users.trader);

        deal(trade.poolToken, users.trader, trade.totalPremium);
        IERC20(trade.poolToken).approve(address(router), trade.totalPremium);

        pool.trade(trade.size, true, trade.totalPremium + trade.totalPremium / 10, address(0));

        vm.stopPrank();
    }

    function _test_exercise_Buy100Options(bool isITM) internal {
        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        uint256 protocolFees = pool.protocolFees();
        assertLt(0 ether, protocolFees);

        vm.warp(poolKey.maturity);
        UD60x18 settlementPrice = getSettlementPrice(isITM);
        oracleAdapter.setPriceAt(poolKey.maturity, settlementPrice);

        vm.prank(users.trader);
        pool.exercise();

        uint256 exerciseValue = toTokenDecimals(getExerciseValue(isITM, trade.size, settlementPrice));
        uint256 exerciseFee = toTokenDecimals(
            pool.exerciseFee(
                address(0),
                trade.size,
                getExerciseValue(isITM, trade.size, settlementPrice),
                poolKey.strike,
                poolKey.isCallPool
            )
        );

        uint256 expectedExerciseValue;
        if (isITM) {
            if (isCallTest) {
                expectedExerciseValue = 16.666666666666666666 ether;
            } else {
                expectedExerciseValue = toTokenDecimals((ud(100 ether) * ud(200 ether)));
            }
        }

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), exerciseValue - exerciseFee);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + trade.totalPremium - exerciseValue - protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(FEE_RECEIVER) - trade.feeReceiverBalance,
            protocolFees + exerciseFee
        );

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
        UD60x18 authorizedCost = isCallTest ? ud(0.01e18) : ud(10e18); // 0.01 ETH or 10 USDC
        enableExerciseSettleAuthorization(users.trader, authorizedCost);
        enableExerciseSettleAuthorization(users.otherTrader, authorizedCost);

        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        vm.startPrank(users.trader);
        pool.setApprovalForAll(users.otherTrader, true);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, (trade.size / TWO).unwrap(), "");
        vm.stopPrank();

        uint256 protocolFees = pool.protocolFees();

        vm.warp(poolKey.maturity);
        UD60x18 settlementPrice = getSettlementPrice(true);
        oracleAdapter.setPrice(settlementPrice);
        oracleAdapter.setPriceAt(poolKey.maturity, settlementPrice);

        uint256 cost;
        {
            address[] memory holders = new address[](2);
            holders[0] = users.trader;
            holders[1] = users.otherTrader;

            cost = toTokenDecimals(authorizedCost);

            vm.prank(users.operator);
            pool.exerciseFor(holders, cost);
        }

        uint256 exerciseValue = toTokenDecimals(getExerciseValue(true, trade.size / TWO, settlementPrice));
        uint256 exerciseFee = toTokenDecimals(
            pool.exerciseFee(
                address(0),
                trade.size / TWO,
                getExerciseValue(true, trade.size / TWO, settlementPrice),
                poolKey.strike,
                poolKey.isCallPool
            )
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.trader), exerciseValue - cost - exerciseFee);
        assertEq(IERC20(trade.poolToken).balanceOf(users.otherTrader), exerciseValue - cost - exerciseFee);

        assertEq(IERC20(trade.poolToken).balanceOf(users.operator), (cost * 2));

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral + trade.totalPremium - (exerciseValue * 2) - protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(FEE_RECEIVER) - trade.feeReceiverBalance,
            protocolFees + (exerciseFee * 2)
        );

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), trade.size);
    }

    function test_exerciseFor_RevertIf_SettlementFailed() public {
        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        UD60x18 settlementPrice = getSettlementPrice(true);
        uint256 poolBalance = IERC20(trade.poolToken).balanceOf(address(pool));
        UD60x18 _poolBalance = fromTokenDecimals(poolBalance);
        UD60x18 poolBalanceInWrappedNativeTokens = isCallTest ? _poolBalance : _poolBalance / settlementPrice;

        enableExerciseSettleAuthorization(users.otherTrader, poolBalanceInWrappedNativeTokens);

        vm.warp(poolKey.maturity);
        oracleAdapter.setPrice(settlementPrice);
        oracleAdapter.setPriceAt(poolKey.maturity, settlementPrice);

        address[] memory holders = new address[](1);
        holders[0] = users.otherTrader;

        vm.expectRevert(IPoolInternal.Pool__SettlementFailed.selector);
        vm.prank(users.operator);
        pool.exerciseFor(holders, poolBalance);
    }

    function _test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue(bool isITM) internal {
        TradeInternal memory trade = _test_exercise_trade_Buy100Options();

        UD60x18 settlementPrice = getSettlementPrice(isITM);
        UD60x18 exerciseValue = getExerciseValue(isITM, trade.size, settlementPrice);
        UD60x18 exerciseFee = pool.exerciseFee(
            address(0),
            trade.size,
            exerciseValue,
            poolKey.strike,
            poolKey.isCallPool
        );

        UD60x18 cost = exerciseValue + ONE;
        enableExerciseSettleAuthorization(users.trader, cost);

        vm.warp(poolKey.maturity);
        oracleAdapter.setPrice(settlementPrice);
        oracleAdapter.setPriceAt(poolKey.maturity, settlementPrice);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        uint256 _cost = toTokenDecimals(cost);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostExceedsPayout.selector,
                cost,
                isITM ? exerciseValue - exerciseFee : ZERO
            )
        );

        vm.prank(users.operator);
        pool.exerciseFor(holders, _cost);
    }

    function test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue_OTM() public {
        _test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue(false);
    }

    function test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue_ITM() public {
        _test_exerciseFor_RevertIf_TotalCostExceedsExerciseValue(true);
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
        vm.warp(poolKey.maturity);
        UD60x18 settlementPrice = getSettlementPrice(false);
        oracleAdapter.setPrice(settlementPrice);

        UD60x18 cost = isCallTest ? ud(0.01e18) : ud(10e18); // 0.01 ETH or 10 USDC
        UD60x18 authorizedCost = isCallTest ? cost - ud(1) : (cost / settlementPrice) - ud(1);
        enableExerciseSettleAuthorization(users.trader, authorizedCost);

        address[] memory holders = new address[](1);
        holders[0] = users.trader;

        uint256 _cost = toTokenDecimals(cost);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__CostNotAuthorized.selector,
                cost / (isCallTest ? ONE : settlementPrice),
                authorizedCost
            )
        );

        vm.prank(users.operator);
        pool.exerciseFor(holders, _cost);
    }

    function test_exerciseFee_ReturnExpectedValue() public {
        UD60x18 size = ud(10e18);
        UD60x18 intrinsicValue = contractsToCollateral(ud(0.2e18) * size);
        UD60x18 exerciseFee = pool.exerciseFee(address(0), size, intrinsicValue, poolKey.strike, isCallTest);
        assertEq(exerciseFee, contractsToCollateral(ud(0.03e18))); // 0.3% of notional

        intrinsicValue = contractsToCollateral(ud(0.02e18) * size);
        exerciseFee = pool.exerciseFee(address(0), size, intrinsicValue, poolKey.strike, isCallTest);
        assertEq(exerciseFee, contractsToCollateral(ud(0.025e18))); // 12.5%  of intrinsicValue
    }
}
