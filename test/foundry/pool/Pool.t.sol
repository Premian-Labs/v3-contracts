// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {DeployTest} from "../Deploy.t.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {Position} from "contracts/libraries/Position.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

abstract contract PoolTest is DeployTest {
    IPool pool;

    function _test_deposit(bool isCall) internal {
        poolKey.isCallPool = isCall;

        address lp = users.lp;

        ERC20Mock token = ERC20Mock(getPoolToken(isCall));
        uint256 _initialCollateral = scaleDecimals(
            initialCollateral(isCall),
            isCall
        );

        vm.startPrank(lp);

        token.mint(lp, _initialCollateral);
        token.approve(address(router), _initialCollateral);

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        UD60x18 depositSize = UD60x18.wrap(1000 ether);

        pool.deposit(
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            depositSize,
            ZERO,
            ONE
        );

        vm.stopPrank();

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        assertEq(pool.balanceOf(lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(token.balanceOf(lp), _initialCollateral - collateralValue);
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_1000_LC() public {
        _test_deposit(poolKey.isCallPool);
    }

    function test_deposit_revertIf_SenderNotOperator() public {
        posKey.operator = users.trader;

        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__NotAuthorized.selector);

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function _test_deposit_revertIf_MarketPriceOutOfMinMax(
        bool isCall
    ) internal {
        _test_deposit(isCall);
        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            posKey.upper + UD60x18.wrap(1),
            posKey.upper
        );

        vm.expectRevert(IPoolInternal.Pool__AboveMaxSlippage.selector);
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            posKey.upper - UD60x18.wrap(10),
            posKey.upper - UD60x18.wrap(1)
        );
    }

    function test_deposit_revertIf_MarketPriceOutOfMinMax() public {
        _test_deposit_revertIf_MarketPriceOutOfMinMax(poolKey.isCallPool);
    }

    function test_deposit_revertIf_ZeroSize() public {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);

        pool.deposit(posKey, ZERO, ZERO, ZERO, ZERO, ONE);
    }

    function test_deposit_revertIf_Expired() public {
        vm.prank(users.lp);

        vm.warp(poolKey.maturity + 1);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_revertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = UD60x18.wrap(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(1.01e18);
        vm.expectRevert(IPoolInternal.Pool__InvalidRange.selector);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_revertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = UD60x18.wrap(0.2501e18);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        vm.expectRevert(IPoolInternal.Pool__TickWidthInvalid.selector);
        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(0.7501e18);
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }
}
