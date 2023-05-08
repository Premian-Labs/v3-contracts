// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, TWO, THREE, FIVE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolFillQuoteRFQTest is DeployTest {
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

    function signQuoteRFQ(
        IPoolInternal.QuoteRFQ memory _quoteRFQ
    ) internal view returns (IPoolInternal.Signature memory) {
        bytes32 hash = pool.quoteRFQHash(_quoteRFQ);

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

        return scaleDecimals(initialCollateral, poolKey.isCallPool);
    }

    function _test_fillQuoteRFQ_Success(bool isCall) internal {
        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        uint256 premium = scaleDecimals(
            contractsToCollateral(quoteRFQ.price * quoteRFQ.size, isCall),
            isCall
        );

        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));

        uint256 collateral = scaleDecimals(
            contractsToCollateral(quoteRFQ.size, isCall),
            isCall
        );

        uint256 protocolFee = pool.takerFee(
            users.trader,
            quoteRFQ.size,
            premium,
            false
        );

        uint256 initialCollateral = getInitialCollateral();

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - collateral + premium - protocolFee,
            "poolToken lp"
        );

        assertEq(
            IERC20(poolToken).balanceOf(users.trader),
            initialCollateral - premium,
            "poolToken trader"
        );

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.SHORT),
            0,
            "short trader"
        );
        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            quoteRFQ.size,
            "long trader"
        );

        assertEq(
            pool.balanceOf(users.lp, PoolStorage.SHORT),
            quoteRFQ.size,
            "short lp"
        );
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0, "long lp");
    }

    function test_fillQuoteRFQ_Success_WithApproval() public {
        mintAndApprove();
        _test_fillQuoteRFQ_Success(poolKey.isCallPool);
    }

    function _test_fillQuoteRFQ_Success_WithReferral(bool isBuy) internal {
        mintAndApprove();

        quoteRFQ.isBuy = isBuy;

        bool isCall = poolKey.isCallPool;
        address token = getPoolToken(isCall);

        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        uint256 premium = scaleDecimals(
            contractsToCollateral(quoteRFQ.price * quoteRFQ.size, isCall),
            isCall
        );

        uint256 protocolFee = pool.takerFee(
            users.trader,
            quoteRFQ.size,
            premium,
            false
        );

        (
            UD60x18 primaryRebatePercent,
            UD60x18 secondaryRebatePercent
        ) = referral.getRebatePercents(users.referrer);

        UD60x18 _primaryRebate = primaryRebatePercent *
            scaleDecimals(protocolFee, isCall);

        UD60x18 _secondaryRebate = secondaryRebatePercent *
            scaleDecimals(protocolFee, isCall);

        uint256 primaryRebate = scaleDecimals(_primaryRebate, isCall);
        uint256 secondaryRebate = scaleDecimals(_secondaryRebate, isCall);
        uint256 totalRebate = primaryRebate + secondaryRebate;

        vm.prank(users.trader);
        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, users.referrer);

        uint256 collateral = scaleDecimals(
            contractsToCollateral(quoteRFQ.size, isCall),
            isCall
        );

        uint256 initialCollateral = getInitialCollateral();

        if (isBuy) {
            assertEq(
                IERC20(token).balanceOf(users.lp),
                initialCollateral - premium
            );

            assertEq(
                IERC20(token).balanceOf(users.trader),
                initialCollateral +
                    premium +
                    totalRebate -
                    collateral -
                    protocolFee
            );
        } else {
            assertEq(
                IERC20(token).balanceOf(users.lp),
                initialCollateral +
                    premium +
                    totalRebate -
                    collateral -
                    protocolFee
            );

            assertEq(
                IERC20(token).balanceOf(users.trader),
                initialCollateral - premium
            );
        }

        assertEq(IERC20(token).balanceOf(address(referral)), totalRebate);
    }

    function test_fillQuoteRFQ_Success_WithReferral_Buy() public {
        _test_fillQuoteRFQ_Success_WithReferral(true);
    }

    function test_fillQuoteRFQ_Success_WithReferral_Sell() public {
        _test_fillQuoteRFQ_Success_WithReferral(false);
    }

    function test_fillQuoteRFQ_RevertIf_QuoteRFQExpired() public {
        quoteRFQ.deadline = block.timestamp - 1 hours;

        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__QuoteRFQExpired.selector);

        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));
    }

    function test_fillQuote_RevertIf_QuotePriceOutOfBounds() public {
        vm.startPrank(users.trader);

        quoteRFQ.price = ud(1);
        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OutOfBoundsPrice.selector,
                quoteRFQ.price
            )
        );
        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));

        quoteRFQ.price = ud(1 ether + 1);
        sig = signQuoteRFQ(quoteRFQ);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OutOfBoundsPrice.selector,
                quoteRFQ.price
            )
        );
        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));
    }

    function test_fillQuoteRFQ_RevertIf_NotSpecifiedTaker() public {
        quoteRFQ.taker = address(0x99999);

        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        vm.prank(users.trader);
        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteRFQTaker.selector);

        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));
    }

    function test_fillQuoteRFQ_RevertIf_Overfilled() public {
        mintAndApprove();

        vm.startPrank(users.trader);

        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size / TWO, sig, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__QuoteRFQOverfilled.selector,
                quoteRFQ.size / TWO,
                quoteRFQ.size,
                quoteRFQ.size
            )
        );
        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));
    }

    function test_fillQuoteRFQ_RevertIf_WrongSignedMessage() public {
        vm.prank(users.trader);
        IPoolInternal.Signature memory sig = signQuoteRFQ(quoteRFQ);

        quoteRFQ.size = quoteRFQ.size * TWO;

        vm.expectRevert(IPoolInternal.Pool__InvalidQuoteRFQSignature.selector);
        pool.fillQuoteRFQ(quoteRFQ, quoteRFQ.size, sig, address(0));
    }
}
