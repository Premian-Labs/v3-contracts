// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTradeTest is DeployTest {
    function _test_trade_Buy50Options_WithApproval(bool isCall) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium);
        IERC20(poolToken).approve(address(router), totalPremium);

        pool.trade(
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_trade_Buy50Options_WithApproval() public {
        _test_trade_Buy50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_trade_Sell50Options_WithApproval(bool isCall) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_trade_Sell50Options_WithApproval() public {
        _test_trade_Sell50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_annihilate_Success(bool isCall) internal {
        deposit(1000 ether);
        vm.startPrank(users.lp);

        address poolToken = getPoolToken(isCall);
        deal(
            poolToken,
            users.lp,
            scaleDecimals(
                contractsToCollateral(UD60x18.wrap(1000 ether), isCall),
                isCall
            )
        );
        IERC20(poolToken).approve(address(router), type(uint256).max);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(200 ether), isCall),
            isCall
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue,
            "1"
        );

        UD60x18 tradeSize = UD60x18.wrap(1000 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        pool.trade(
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium,
            "poolToken lp 0"
        );

        vm.warp(block.timestamp + 60);
        UD60x18 withdrawSize = UD60x18.wrap(300 ether);

        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(
            pool.balanceOf(users.lp, PoolStorage.SHORT),
            tradeSize,
            "lp short 1"
        );
        assertEq(
            pool.balanceOf(users.lp, PoolStorage.LONG),
            withdrawSize,
            "lp long 1"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.LONG),
            tradeSize - withdrawSize,
            "pool long 1"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium,
            "poolToken lp 1"
        );

        UD60x18 annihilateSize = UD60x18.wrap(100 ether);
        pool.annihilate(annihilateSize);

        assertEq(
            pool.balanceOf(users.lp, PoolStorage.SHORT),
            tradeSize - annihilateSize,
            "lp short 2"
        );
        assertEq(
            pool.balanceOf(users.lp, PoolStorage.LONG),
            withdrawSize - annihilateSize,
            "lp long 2"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            totalPremium +
                scaleDecimals(
                    contractsToCollateral(annihilateSize, isCall),
                    isCall
                ),
            "poolToken lp 2"
        );
    }

    function test_annihilate_Success() public {
        _test_annihilate_Success(poolKey.isCallPool);
    }

    function _test_swapAndTrade_Buy500Options(
        bool isCall,
        bool useMsgValue
    ) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        uint256 swapQuote = getSwapQuoteExactOutput(
            swapToken,
            poolToken,
            totalPremium
        );

        if (useMsgValue) {
            startHoax(users.trader);
        } else {
            vm.startPrank(users.trader);
            deal(swapToken, users.trader, swapQuote);
            IERC20(swapToken).approve(address(router), type(uint256).max);
        }

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            poolToken,
            swapQuote,
            totalPremium,
            users.trader
        );

        pool.swapAndTrade{value: useMsgValue ? swapQuote : 0}(
            swapArgs,
            tradeSize,
            true,
            totalPremium + totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
    }

    function test_swapAndTrade_Buy50Options_WithApproval() public {
        _test_swapAndTrade_Buy500Options(poolKey.isCallPool, false);
    }

    function test_swapAndTrade_Buy50Options_WithETH() public {
        if (poolKey.isCallPool) return;
        _test_swapAndTrade_Buy500Options(poolKey.isCallPool, true);
    }

    function _test_swapAndTrade_Sell50Options_WithApproval(
        bool isCall
    ) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);

        uint256 swapQuote = getSwapQuoteExactOutput(
            swapToken,
            poolToken,
            collateralScaled
        );
        deal(swapToken, users.trader, swapQuote);
        IERC20(swapToken).approve(address(router), type(uint256).max);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            poolToken,
            swapQuote,
            collateralScaled,
            users.trader
        );

        pool.swapAndTrade(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(IERC20(poolToken).balanceOf(users.trader), totalPremium);
    }

    function test_swapAndTrade_Sell50Options_WithApproval() public {
        _test_swapAndTrade_Sell50Options_WithApproval(poolKey.isCallPool);
    }

    function _test_swapAndTrade_RevertIf_InvalidSwapTokenOut(
        bool isCall
    ) internal {
        vm.prank(users.lp);

        address swapToken = getSwapToken(isCall);
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            swapToken,
            0,
            0,
            users.trader
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidSwapTokenOut.selector,
                swapToken,
                getPoolToken(isCall)
            )
        );
        pool.swapAndTrade(swapArgs, ZERO, true, 0, Permit2.emptyPermit());
    }

    function test_swapAndTrade_RevertIf_InvalidSwapTokenOut() public {
        _test_swapAndTrade_RevertIf_InvalidSwapTokenOut(poolKey.isCallPool);
    }

    function _test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenSellingLongs(
        bool isCall
    ) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        UD60x18 tradeSize0 = UD60x18.wrap(500 ether);

        (uint256 totalPremium0, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize0,
            true
        );

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium0);
        IERC20(poolToken).approve(address(router), totalPremium0);

        pool.trade(
            tradeSize0,
            true,
            totalPremium0 + totalPremium0 / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize0);
        assertEq(IERC20(poolToken).balanceOf(users.trader), 0);
        assertEq(IERC20(swapToken).balanceOf(users.trader), 0);

        //

        UD60x18 tradeSize = UD60x18.wrap(300 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(1000 ether), isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

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

        (, Position.Delta memory delta, , ) = pool.tradeAndSwap(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertGt(delta.collateral.unwrap(), 0);

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.SHORT),
            0,
            "trader short"
        );
        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            tradeSize0 - tradeSize,
            "trader long"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.LONG),
            0,
            "pool long"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.SHORT),
            tradeSize0 - tradeSize,
            "pool short"
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            collateralScaled + totalPremium0 - totalPremium,
            "pool token"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            0,
            "poolToken trader"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            swapQuote,
            "swapToken trader"
        );
    }

    function test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenSellingLongs()
        public
    {
        _test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenSellingLongs(
            poolKey.isCallPool
        );
    }

    function _test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenClosingShorts(
        bool isCall
    ) internal {
        posKey.orderType = Position.OrderType.LC;
        deposit(1000 ether);

        uint256 initialPoolCollateral = scaleDecimals(
            contractsToCollateral(UD60x18.wrap(200 ether), isCall),
            isCall
        );

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        UD60x18 tradeSize0 = UD60x18.wrap(500 ether);

        (uint256 totalPremium0, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize0,
            false
        );

        uint256 traderCollateral0 = scaleDecimals(
            contractsToCollateral(tradeSize0, isCall),
            isCall
        );

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, traderCollateral0);
        IERC20(poolToken).approve(address(router), traderCollateral0);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialPoolCollateral,
            "pool token 0"
        );

        pool.trade(
            tradeSize0,
            false,
            totalPremium0 - totalPremium0 / 10,
            Permit2.emptyPermit()
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize0);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize0);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialPoolCollateral + traderCollateral0 - totalPremium0,
            "pool token 0"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            totalPremium0,
            "poolToken trader 0"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            0,
            "swapToken trader 0"
        );

        //

        UD60x18 tradeSize = UD60x18.wrap(300 ether);
        uint256 traderCollateral = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            true
        );

        uint256 swapQuote = getSwapQuoteExactInput(
            poolToken,
            swapToken,
            traderCollateral - totalPremium
        );

        {
            IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
                poolToken,
                swapToken,
                traderCollateral - totalPremium,
                swapQuote,
                users.trader
            );

            (, Position.Delta memory delta, , ) = pool.tradeAndSwap(
                swapArgs,
                tradeSize,
                true,
                totalPremium + totalPremium / 10,
                Permit2.emptyPermit()
            );

            assertGt(delta.collateral.unwrap(), 0);
        }

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.SHORT),
            tradeSize0 - tradeSize,
            "trader short"
        );
        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            0,
            "trader long"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.LONG),
            tradeSize0 - tradeSize,
            "pool long"
        );
        assertEq(
            pool.balanceOf(address(pool), PoolStorage.SHORT),
            0,
            "pool short"
        );

        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            initialPoolCollateral +
                traderCollateral0 -
                totalPremium0 -
                traderCollateral +
                totalPremium,
            "pool token"
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            totalPremium0,
            "poolToken trader"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            swapQuote,
            "swapToken trader"
        );
    }

    function test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenClosingShorts()
        public
    {
        _test_tradeAndSwap_Swap_IfPositiveDeltaCollateral_WhenClosingShorts(
            poolKey.isCallPool
        );
    }

    function _test_tradeAndSwap_NotSwap_IfNegativeDeltaCollateral(
        bool isCall
    ) internal {
        deposit(1000 ether);

        UD60x18 tradeSize = UD60x18.wrap(500 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

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

        (, Position.Delta memory delta, , ) = pool.tradeAndSwap(
            swapArgs,
            tradeSize,
            false,
            totalPremium - totalPremium / 10,
            Permit2.emptyPermit()
        );

        assertLt(delta.collateral.unwrap(), 0);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.LONG), tradeSize);
        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            totalPremium,
            "poolToken balance"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            0,
            "swapToken balance"
        );
    }

    function test_tradeAndSwap_NotSwap_IfNegativeDeltaCollateral() public {
        _test_tradeAndSwap_NotSwap_IfNegativeDeltaCollateral(
            poolKey.isCallPool
        );
    }

    function _test_tradeAndSwap_RevertIf_InvalidSwapTokenIn(
        bool isCall
    ) internal {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        UD60x18 tradeSize0 = UD60x18.wrap(500 ether);

        (uint256 totalPremium0, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize0,
            true
        );

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, totalPremium0);
        IERC20(poolToken).approve(address(router), totalPremium0);

        pool.trade(
            tradeSize0,
            true,
            totalPremium0 + totalPremium0 / 10,
            Permit2.emptyPermit()
        );

        //

        UD60x18 tradeSize = UD60x18.wrap(300 ether);
        uint256 collateralScaled = scaleDecimals(
            contractsToCollateral(tradeSize, isCall),
            isCall
        );

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            false
        );

        deal(poolToken, users.trader, collateralScaled);
        IERC20(poolToken).approve(address(router), collateralScaled);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidSwapTokenIn.selector,
                swapToken,
                poolToken
            )
        );

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
