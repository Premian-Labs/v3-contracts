// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTradeAndSwapTest is DeployTest {
    function _test_tradeAndSwap_Sell50OptionsAndSwapPremium_WithApproval(
        bool isCall
    ) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        uint256 totalPremium = pool.getTradeQuote(tradeSize, false);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        uint256 swapQuote = getSwapQuoteExactInput(
            poolToken,
            swapToken,
            totalPremium
        );
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
            poolToken,
            swapToken,
            totalPremium,
            swapQuote,
            users.trader
        );

        pool.tradeAndSwap(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            0,
            "poolToken balance"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            swapQuote,
            "swapToken balance"
        );
    }

    function test_tradeAndSwap_Sell50OptionsAndSwapPremium_WithApproval()
        public
    {
        _test_tradeAndSwap_Sell50OptionsAndSwapPremium_WithApproval(
            poolKey.isCallPool
        );
    }

    function _test_tradeAndSwap_RevertIf_InvalidSwapTokenIn(
        bool isCall
    ) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        uint256 totalPremium = pool.getTradeQuote(tradeSize, false);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        vm.expectRevert(IPoolInternal.Pool__InvalidSwapTokenIn.selector);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
            swapToken,
            swapToken,
            0,
            0,
            users.trader
        );

        pool.tradeAndSwap(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );
    }

    function test_tradeAndSwap_RevertIf_InvalidSwapTokenIn() public {
        _test_tradeAndSwap_RevertIf_InvalidSwapTokenIn(poolKey.isCallPool);
    }
}
