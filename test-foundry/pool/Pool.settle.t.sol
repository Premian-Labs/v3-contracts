// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

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
    function _test_settle_trade_Sell100Options(
        bool isCall
    ) internal returns (TradeInternal memory trade) {
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        deposit(depositSize);

        trade.initialCollateral = scaleDecimals(
            contractsToCollateral(depositSize, isCall) *
                posKey.lower.avg(posKey.upper),
            isCall
        );

        trade.size = UD60x18.wrap(100 ether);

        trade.traderCollateral = scaleDecimals(
            contractsToCollateral(trade.size, isCall),
            isCall
        );

        (trade.totalPremium, ) = pool.getQuoteAMM(trade.size, false);

        trade.poolToken = getPoolToken(isCall);
        trade.feeReceiverBalance = IERC20(trade.poolToken).balanceOf(
            feeReceiver
        );

        vm.startPrank(users.trader);

        deal(trade.poolToken, users.trader, trade.traderCollateral);
        IERC20(trade.poolToken).approve(
            address(router),
            trade.traderCollateral
        );

        pool.trade(
            trade.size,
            false,
            trade.totalPremium - trade.totalPremium / 10,
            Permit2.emptyPermit()
        );

        vm.stopPrank();
    }

    function _test_settle_Sell100Options(bool isCall, bool isITM) internal {
        TradeInternal memory trade = _test_settle_trade_Sell100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);

        pool.settle(users.trader);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, isITM, trade.size, settlementPrice),
            isCall
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            trade.traderCollateral + trade.totalPremium - exerciseValue
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral +
                exerciseValue -
                trade.totalPremium -
                protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), trade.size);
    }

    function test_settle_Sell100Options_ITM() public {
        _test_settle_Sell100Options(poolKey.isCallPool, true);
    }

    function test_settle_Sell100Options_OTM() public {
        _test_settle_Sell100Options(poolKey.isCallPool, false);
    }

    function test_settle_RevertIf_OptionNotExpired() public {
        vm.expectRevert(IPoolInternal.Pool__OptionNotExpired.selector);
        pool.settle(users.trader);
    }

    function _test_settle_automatic_Sell100Options(
        bool isCall,
        bool isITM
    ) internal {
        UD60x18 settlementPrice = handleExerciseSettleAuthorization(
            isCall,
            isITM,
            users.trader,
            0.1 ether
        );

        TradeInternal memory trade = _test_settle_trade_Sell100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        uint256 txCost = scaleDecimals(UD60x18.wrap(0.09 ether), isCall);
        uint256 fee = scaleDecimals(UD60x18.wrap(0.01 ether), isCall);
        uint256 totalCost = txCost + fee;

        vm.warp(poolKey.maturity);
        vm.prank(users.agent);

        pool.settle(users.trader, txCost, fee);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, isITM, trade.size, settlementPrice),
            isCall
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(users.trader),
            trade.traderCollateral +
                trade.totalPremium -
                exerciseValue -
                totalCost
        );

        assertEq(IERC20(trade.poolToken).balanceOf(users.agent), totalCost);

        assertEq(
            IERC20(trade.poolToken).balanceOf(address(pool)),
            trade.initialCollateral +
                exerciseValue -
                trade.totalPremium -
                protocolFees
        );

        assertEq(
            IERC20(trade.poolToken).balanceOf(feeReceiver) -
                trade.feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.protocolFees(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), trade.size);
    }

    function test_settle_automatic_Sell100Options_ITM() public {
        _test_settle_automatic_Sell100Options(poolKey.isCallPool, true);
    }

    function test_settle_automatic_Sell100Options_OTM() public {
        _test_settle_automatic_Sell100Options(poolKey.isCallPool, false);
    }

    function test_settle_automatic_RevertIf_TotalCostExceedsCollateralValue()
        public
    {
        bool isCall = poolKey.isCallPool;

        UD60x18 settlementPrice = getSettlementPrice(isCall, false);
        UD60x18 quote = isCall ? ONE : settlementPrice.inv();
        oracleAdapter.setQuote(quote);
        oracleAdapter.setQuoteFrom(settlementPrice);

        TradeInternal memory trade = _test_settle_trade_Sell100Options(isCall);

        UD60x18 exerciseValue = getExerciseValue(
            isCall,
            false,
            trade.size,
            settlementPrice
        );

        UD60x18 collateral = getCollateralValue(
            isCall,
            trade.size,
            exerciseValue
        );

        uint256 txCost = collateral.unwrap();
        uint256 fee = 1 wei;
        uint256 totalCost = txCost + fee;

        address[] memory agents = new address[](1);
        agents[0] = users.agent;

        vm.startPrank(users.trader);
        userSettings.setAuthorizedAgents(agents);

        // if !isCall, convert collateral to WETH
        userSettings.setAuthorizedTxCostAndFee(
            isCall
                ? totalCost
                : (UD60x18.wrap(scaleDecimalsTo(totalCost, isCall)) * quote)
                    .unwrap()
        );

        vm.stopPrank();

        vm.warp(poolKey.maturity);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TotalCostExceedsCollateralValue.selector,
                scaleDecimalsTo(totalCost, isCall),
                collateral.unwrap()
            )
        );

        vm.prank(users.agent);
        pool.settle(users.trader, txCost, fee);
    }

    function test_settle_automatic_RevertIf_UnauthorizedAgent() public {
        vm.expectRevert(IPoolInternal.Pool__UnauthorizedAgent.selector);
        vm.prank(users.agent);
        pool.settle(users.trader, 0, 0);
    }

    function test_settle_automatic_RevertIf_UnauthorizedTxCostAndFee() public {
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
        pool.settle(users.trader, txCost, fee);
    }
}
