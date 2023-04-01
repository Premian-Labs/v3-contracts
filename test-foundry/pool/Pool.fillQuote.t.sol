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
    function init() internal {
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
        init();

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
        init();

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
}
