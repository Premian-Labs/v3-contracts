// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, TWO, THREE, FIVE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolFillQuoteOBTest is DeployTest {
    function mintAndApprove() internal {
        uint256 initialCollateral = getInitialCollateral();
        address poolToken = getPoolToken();

        deal(poolToken, users.lp, initialCollateral);
        deal(poolToken, users.trader, initialCollateral);

        vm.prank(users.lp);
        IERC20(poolToken).approve(address(router), initialCollateral);

        vm.prank(users.trader);
        IERC20(poolToken).approve(address(router), initialCollateral);
    }

    function signQuoteOB(IPoolInternal.QuoteOB memory _quoteOB) internal view returns (IPoolInternal.Signature memory) {
        bytes32 hash = pool.quoteOBHash(_quoteOB);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            1, // 1 = users.lp
            hash
        );

        return IPoolInternal.Signature(v, r, s);
    }

    function getInitialCollateral() internal view returns (uint256) {
        UD60x18 initialCollateral = ud(10 ether);

        if (!poolKey.isCallPool) {
            initialCollateral = initialCollateral * poolKey.strike;
        }

        return toTokenDecimals(initialCollateral);
    }

    function test_fillQuoteOB_Success_WithApproval() public {
        mintAndApprove();

        address poolToken = getPoolToken();

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        uint256 premium = toTokenDecimals(contractsToCollateral(quoteOB.price * quoteOB.size));

        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));

        uint256 collateral = toTokenDecimals(contractsToCollateral(quoteOB.size));

        uint256 protocolFee = pool.takerFee(users.trader, quoteOB.size, premium, false, true);

        uint256 initialCollateral = getInitialCollateral();

        assertEq(IERC20(poolToken).balanceOf(users.lp), initialCollateral - collateral + premium, "poolToken lp");

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            initialCollateral - premium - protocolFee,
            "poolToken trader"
        );

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0, "short trader");
        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), quoteOB.size, "long trader");

        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), quoteOB.size, "short lp");
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0, "long lp");
    }

    function _test_fillQuoteOB_Success_WithReferral(bool isBuy) internal {
        mintAndApprove();
        quoteOB.isBuy = isBuy;
        address token = getPoolToken();

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        uint256 premium = toTokenDecimals(contractsToCollateral(quoteOB.price * quoteOB.size));
        uint256 protocolFee = pool.takerFee(users.trader, quoteOB.size, premium, false, true);

        (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent * fromTokenDecimals(protocolFee);
        UD60x18 _secondaryRebate = secondaryRebatePercent * fromTokenDecimals(protocolFee);

        uint256 primaryRebate = toTokenDecimals(_primaryRebate);
        uint256 secondaryRebate = toTokenDecimals(_secondaryRebate);
        uint256 totalRebate = primaryRebate + secondaryRebate;

        vm.prank(users.trader);
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, users.referrer);

        uint256 collateral = toTokenDecimals(contractsToCollateral(quoteOB.size));
        uint256 initialCollateral = getInitialCollateral();

        if (isBuy) {
            assertEq(IERC20(token).balanceOf(users.lp), initialCollateral - premium);

            assertEq(IERC20(token).balanceOf(users.trader), initialCollateral + premium - collateral - protocolFee);
        } else {
            assertEq(IERC20(token).balanceOf(users.lp), initialCollateral + premium - collateral);

            assertEq(IERC20(token).balanceOf(users.trader), initialCollateral - premium - protocolFee);
        }

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_fillQuoteOB_Success_WithReferral_Buy() public {
        _test_fillQuoteOB_Success_WithReferral(true);
    }

    function test_fillQuoteOB_Success_WithReferral_Sell() public {
        _test_fillQuoteOB_Success_WithReferral(false);
    }

    function test_fillQuoteOB_RevertIf_OptionExpired() public {
        mintAndApprove();
        vm.startPrank(users.trader);
        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);
        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_isQuoteOBValid_RevertIf_OptionExpired() public {
        mintAndApprove();
        vm.startPrank(users.trader);
        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);
        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.isQuoteOBValid(users.trader, quoteOB, quoteOB.size, sig);
    }

    function test_fillQuoteOB_RevertIf_QuoteOBExpired() public {
        quoteOB.deadline = block.timestamp - 1 hours;

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__QuoteOBExpired.selector);

        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_fillQuote_RevertIf_QuotePriceOutOfBounds() public {
        vm.startPrank(users.trader);

        quoteOB.price = ud(1 ether + 1);
        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OutOfBoundsPrice.selector, quoteOB.price));
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_fillQuoteOB_RevertIf_NotSpecifiedTaker() public {
        quoteOB.taker = address(0x99999);

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteOBTaker.selector);

        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_fillQuoteOB_RevertIf_Overfilled() public {
        mintAndApprove();

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        pool.fillQuoteOB(quoteOB, quoteOB.size / TWO, sig, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__QuoteOBOverfilled.selector,
                quoteOB.size / TWO,
                quoteOB.size,
                quoteOB.size
            )
        );
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_fillQuoteOB_RevertIf_WrongSignedMessage() public {
        vm.prank(users.trader);
        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        quoteOB.size = quoteOB.size * TWO;

        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteOBSignature.selector);
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_cancelQuotesOB_Success() public {
        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        bytes32[] memory quoteOBHashes = new bytes32[](1);
        quoteOBHashes[0] = pool.quoteOBHash(quoteOB);

        vm.prank(users.lp);
        pool.cancelQuotesOB(quoteOBHashes);

        vm.expectRevert(IPoolInternal.Pool__QuoteOBCancelled.selector);
        vm.prank(users.trader);
        pool.fillQuoteOB(quoteOB, quoteOB.size, sig, address(0));
    }

    function test_getQuoteOBFilledAmount_ReturnExpectedValue() public {
        mintAndApprove();

        IPoolInternal.Signature memory sig = signQuoteOB(quoteOB);

        vm.prank(users.trader);
        pool.fillQuoteOB(quoteOB, quoteOB.size / TWO, sig, address(0));

        bytes32 quoteOBHash = pool.quoteOBHash(quoteOB);
        assertEq(pool.getQuoteOBFilledAmount(quoteOB.provider, quoteOBHash), quoteOB.size / TWO);
    }
}
