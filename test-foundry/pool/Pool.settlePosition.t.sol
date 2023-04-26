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
}
