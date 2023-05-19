// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolGetQuoteAMMTest is DeployTest {
    function _test_getQuoteAMM_ReturnBuyQuote(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        UD60x18 price = posKey.lower;
        UD60x18 nextPrice = ud(0.2e18);
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(
            users.trader,
            tradeSize,
            scaleDecimals(tradeSize * avgPrice, isCall),
            true
        );

        uint256 quote = scaleDecimals(
            contractsToCollateral(tradeSize * avgPrice, isCall),
            isCall
        ) + takerFee;

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );
        assertEq(totalPremium, quote);
    }

    function test_getQuoteAMM_ReturnBuyQuote() public {
        _test_getQuoteAMM_ReturnBuyQuote(poolKey.isCallPool);
    }

    function _test_getQuoteAMM_ReturnSellQuote(bool isCall) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = ud(500 ether);
        UD60x18 price = posKey.upper;
        UD60x18 nextPrice = ud(0.2e18);
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(
            users.trader,
            tradeSize,
            scaleDecimals(tradeSize * avgPrice, isCall),
            true
        );

        uint256 quote = scaleDecimals(
            contractsToCollateral(tradeSize * avgPrice, isCall),
            isCall
        ) - takerFee;

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );
        assertEq(totalPremium, quote);
    }

    function test_getQuoteAMM_ReturnSellQuote() public {
        _test_getQuoteAMM_ReturnSellQuote(poolKey.isCallPool);
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
}
