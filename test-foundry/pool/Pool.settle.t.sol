// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSettleTest is DeployTest {
    function sell100Options(
        bool isCall
    ) internal returns (address, uint256, uint256, uint256, uint256, UD60x18) {
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        deposit(depositSize);

        uint256 initalCollateral = scaleDecimals(
            contractsToCollateral(depositSize, isCall) *
                posKey.lower.avg(posKey.upper),
            isCall
        );

        UD60x18 tradeSize = UD60x18.wrap(100 ether);

        uint256 traderCollateral = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(tradeSize, false);

        address poolToken = getPoolToken(isCall);
        uint256 feeReceiverBalance = IERC20(poolToken).balanceOf(feeReceiver);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, traderCollateral);
        IERC20(poolToken).approve(address(router), traderCollateral);

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        vm.stopPrank();

        return (
            poolToken,
            initalCollateral,
            traderCollateral,
            totalPremium,
            feeReceiverBalance,
            tradeSize
        );
    }

    function _test_settle_Sell100Options(bool isCall, bool isITM) internal {
        (
            address poolToken,
            uint256 initalCollateral,
            uint256 traderCollateral,
            uint256 totalPremium,
            uint256 feeReceiverBalance,
            UD60x18 tradeSize
        ) = sell100Options(isCall);

        uint256 protocolFees = pool.protocolFees();

        UD60x18 settlementPrice = getSettlementPrice(isCall, isITM);
        oracleAdapter.setQuoteFrom(settlementPrice);

        vm.warp(poolKey.maturity);

        pool.settle(users.trader);

        uint256 exerciseValue = scaleDecimals(
            getExerciseValue(isCall, isITM, tradeSize, settlementPrice),
            isCall
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            traderCollateral + totalPremium - exerciseValue
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initalCollateral + exerciseValue - totalPremium - protocolFees
        );

        assertEq(
            IERC20(poolToken).balanceOf(feeReceiver) - feeReceiverBalance,
            protocolFees
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
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
}
