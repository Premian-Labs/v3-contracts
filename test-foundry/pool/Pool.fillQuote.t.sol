// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, TWO} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolFillQuoteTest is DeployTest {
    function mintAndApprove() internal {
        uint256 initialCollateral = getInitialCollateral();
        address poolToken = getPoolToken(poolKey.isCallPool);

        deal(poolToken, users.lp, initialCollateral);
        deal(poolToken, users.trader, initialCollateral);

        vm.prank(users.lp);
        IERC20(poolToken).approve(address(router), initialCollateral);

        vm.prank(users.trader);
        IERC20(poolToken).approve(address(router), initialCollateral);
    }

    function signQuote(
        IPoolInternal.TradeQuote memory _tradeQuote
    ) internal view returns (IPoolInternal.Signature memory) {
        bytes32 hash = pool.tradeQuoteHash(_tradeQuote);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            1, // 1 = users.lp
            hash
        );

        return IPoolInternal.Signature(v, r, s);
    }

    function getInitialCollateral() internal view returns (uint256) {
        UD60x18 initialCollateral = UD60x18.wrap(10 ether);

        if (!poolKey.isCallPool) {
            initialCollateral = initialCollateral * poolKey.strike;
        }

        return scaleDecimals(initialCollateral, poolKey.isCallPool);
    }

    function _test_fillQuote_Success_WithApproval(bool isCall) internal {
        mintAndApprove();

        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());

        uint256 premium = scaleDecimals(
            contractsToCollateral(tradeQuote.price * tradeQuote.size, isCall),
            isCall
        );

        uint256 collateral = scaleDecimals(
            contractsToCollateral(tradeQuote.size, isCall),
            isCall
        );

        uint256 protocolFee = pool.takerFee(tradeQuote.size, premium, false);

        uint256 initialCollateral = getInitialCollateral();

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - collateral + premium - protocolFee
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            initialCollateral - premium
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            tradeQuote.size
        );

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), tradeQuote.size);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
    }

    function test_fillQuote_Success_WithApproval() public {
        _test_fillQuote_Success_WithApproval(poolKey.isCallPool);
    }

    function test_fillQuote_RevertIf_QuoteExpired() public {
        tradeQuote.deadline = block.timestamp - 1 hours;

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__QuoteExpired.selector);

        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());
    }

    function test_fillQuote_RevertIf_QuotePriceOutOfBounds() public {
        vm.startPrank(users.trader);

        tradeQuote.price = UD60x18.wrap(1);
        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        vm.expectRevert(IPoolInternal.Pool__OutOfBoundsPrice.selector);
        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());

        tradeQuote.price = UD60x18.wrap(1 ether + 1);
        sig = signQuote(tradeQuote);

        vm.expectRevert(IPoolInternal.Pool__OutOfBoundsPrice.selector);
        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());
    }

    function test_fillQuote_RevertIf_NotSpecifiedTaker() public {
        tradeQuote.taker = address(0x99999);

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteTaker.selector);

        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());
    }

    function test_fillQuote_RevertIf_Overfilled() public {
        mintAndApprove();

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        pool.fillQuote(
            tradeQuote,
            tradeQuote.size / TWO,
            sig,
            Permit2.emptyPermit()
        );

        vm.expectRevert(IPoolInternal.Pool__QuoteOverfilled.selector);
        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());
    }

    function test_fillQuote_RevertIf_WrongSignedMessage() public {
        vm.prank(users.trader);
        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        tradeQuote.size = tradeQuote.size * TWO;

        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteSignature.selector);
        pool.fillQuote(tradeQuote, tradeQuote.size, sig, Permit2.emptyPermit());
    }

    function _test_fillQuoteAndSwap_Success_WithApproval(bool isCall) internal {
        mintAndApprove();

        tradeQuote.isBuy = true;

        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        vm.startPrank(users.trader);

        uint256 premium = scaleDecimals(
            contractsToCollateral(tradeQuote.price * tradeQuote.size, isCall),
            isCall
        );
        uint256 protocolFee = pool.takerFee(tradeQuote.size, premium, false);
        uint256 initialCollateral = getInitialCollateral();

        uint256 swapQuote = getSwapQuoteExactInput(
            poolToken,
            swapToken,
            premium - protocolFee
        );
        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactInput(
            poolToken,
            swapToken,
            premium - protocolFee,
            swapQuote,
            users.trader
        );

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        pool.fillQuoteAndSwap(
            swapArgs,
            tradeQuote,
            tradeQuote.size,
            sig,
            Permit2.emptyPermit()
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - premium,
            "poolToken LP"
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

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.SHORT),
            tradeQuote.size
        );
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 0);

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), tradeQuote.size);
    }

    function test_fillQuoteAndSwap_Success_WithApproval() public {
        _test_fillQuoteAndSwap_Success_WithApproval(poolKey.isCallPool);
    }

    function _test_swapAndFillQuote_Success_WithApproval(bool isCall) internal {
        uint256 initialCollateral = getInitialCollateral();
        address poolToken = getPoolToken(isCall);
        address swapToken = getSwapToken(isCall);

        deal(poolToken, users.lp, initialCollateral);

        vm.prank(users.lp);
        IERC20(poolToken).approve(address(router), initialCollateral);

        //

        uint256 premium = scaleDecimals(
            contractsToCollateral(tradeQuote.price * tradeQuote.size, isCall),
            isCall
        );

        vm.startPrank(users.trader);

        uint256 swapQuote = getSwapQuoteExactOutput(
            swapToken,
            poolToken,
            premium
        );

        deal(swapToken, users.trader, swapQuote);
        IERC20(swapToken).approve(address(router), type(uint256).max);

        IPoolInternal.SwapArgs memory swapArgs = getSwapArgsExactOutput(
            swapToken,
            poolToken,
            swapQuote,
            premium,
            users.trader
        );

        IPoolInternal.Signature memory sig = signQuote(tradeQuote);

        pool.swapAndFillQuote(
            swapArgs,
            tradeQuote,
            tradeQuote.size,
            sig,
            Permit2.emptyPermit()
        );

        uint256 collateral = scaleDecimals(
            contractsToCollateral(tradeQuote.size, isCall),
            isCall
        );

        uint256 protocolFee = pool.takerFee(tradeQuote.size, premium, false);

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - collateral + premium - protocolFee,
            "poolToken LP"
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            0,
            "poolToken trader"
        );
        assertEq(
            IERC20(swapToken).balanceOf(users.trader),
            0,
            "swapToken trader"
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            tradeQuote.size
        );

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), tradeQuote.size);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
    }

    function test_swapAndFillQuote_Success_WithApproval() public {
        _test_swapAndFillQuote_Success_WithApproval(poolKey.isCallPool);
    }
}
