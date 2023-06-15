// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolGetQuoteAMMTest is DeployTest {
    function test_getQuoteAMM_ReturnBuyQuote() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        UD60x18 price = posKey.lower;
        UD60x18 nextPrice = ud(0.2e18);
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(users.trader, tradeSize, scaleDecimals(tradeSize * avgPrice), true);

        uint256 quote = scaleDecimals(contractsToCollateral(tradeSize * avgPrice)) + takerFee;

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, true);
        assertEq(totalPremium, quote);
    }

    function test_getQuoteAMM_ReturnSellQuote() public {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        UD60x18 price = posKey.upper;
        UD60x18 nextPrice = ud(0.2e18);
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(users.trader, tradeSize, scaleDecimals(tradeSize * avgPrice), true);

        uint256 quote = scaleDecimals(contractsToCollateral(tradeSize * avgPrice)) - takerFee;

        (uint256 totalPremium, ) = pool.getQuoteAMM(users.trader, tradeSize, false);
        assertEq(totalPremium, quote);
    }

    function test_getQuoteAMM_RevertIf_NotEnoughLiquidityToBuy() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        vm.expectRevert(IPoolInternal.Pool__InsufficientLiquidity.selector);
        pool.getQuoteAMM(users.trader, ud(1001 ether), true);
    }

    function test_getQuoteAMM_RevertIf_NotEnoughLiquidityToSell() public {
        deposit(1000 ether);

        vm.expectRevert(IPoolInternal.Pool__InsufficientLiquidity.selector);
        pool.getQuoteAMM(users.trader, ud(1001 ether), false);
    }

    function test_getQuoteAMM_MultipleRangeOrders() public {
        // bug was detected due to rounding errors.
        // update:  with the new restricted tick widths this test is not anymore as critical
        //          and can be viewed more as an integration test
        posKey.lower = ud(0.001 ether);
        posKey.upper = ud(0.129 ether);
        posKey.orderType = Position.OrderType.LC;
        deposit(10 ether);
        (uint256 totalNetPremium, uint256 totalTakerFee) = pool.getQuoteAMM(address(1), ud(9 ether), false);
        // nextPrice = 0.129 - 9 / 10 * (0.129 - 0.001) = 0.0138
        // totalPremium = (0.0138 + 0.129) / 2 * 9 = 0.6426
        // totalNetPremium = 0.6426 - 0.027 = 0.6156
        // there will be a rounding error due to the liquidity rate
        // put case is with 6 decimals and needs to be multiplied by the strike value (1000)
        assertEq(totalNetPremium, isCallTest ? 0.6156 ether : 615.6e6);
        assertEq(totalTakerFee, isCallTest ? 0.027 ether : 27e6);
        posKey.lower = ud(0.104 ether);
        posKey.upper = ud(0.120 ether);
        posKey.orderType = Position.OrderType.LC;
        deposit(5 ether);
        (uint256 totalNetPremiumUpdated, uint256 totalTakerFeeUpdated) = pool.getQuoteAMM(
            address(1),
            ud(9 ether),
            false
        );
        assertEq(totalNetPremiumUpdated, isCallTest ? 0.915568750 ether : 915.568750e6);
        assertEq(totalTakerFeeUpdated, isCallTest ? 0.058031250 ether : 58.031250e6);
    }
}
