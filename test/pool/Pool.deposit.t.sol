// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Pricing} from "contracts/libraries/Pricing.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolDepositTest is DeployTest {
    function test_deposit_1000_LC_WithToken() public {
        poolKey.isCallPool = isCallTest;

        IERC20 token = IERC20(getPoolToken());
        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice);

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(token.balanceOf(users.lp), initialCollateral - collateralValue);
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_RevertIf_SenderNotOperator() public {
        posKey.operator = users.trader;

        vm.prank(users.lp);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.lp));

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_MarketPriceOutOfMinMax() public {
        poolKey.isCallPool = isCallTest;
        deposit(1000 ether);
        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        UD60x18 minPrice = posKey.upper + ud(1);
        UD60x18 maxPrice = posKey.upper;
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.deposit(posKey, ZERO, ZERO, THREE, minPrice, maxPrice);

        minPrice = posKey.upper - ud(10);
        maxPrice = posKey.upper - ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__AboveMaxSlippage.selector, posKey.upper, minPrice, maxPrice)
        );
        pool.deposit(posKey, ZERO, ZERO, THREE, minPrice, maxPrice);
    }

    function test_deposit_RevertIf_ZeroSize() public {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);

        pool.deposit(posKey, ZERO, ZERO, ZERO, ZERO, ONE);
    }

    function test_deposit_RevertIf_Expired() public {
        vm.prank(users.lp);

        vm.warp(poolKey.maturity + 1);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);

        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = ud(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(1.01e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__InvalidRange.selector, posKey.lower, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_deposit_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ud(0.2501e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__TickWidthInvalid.selector, posKey.lower));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(0.7501e18);
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__TickWidthInvalid.selector, posKey.upper));
        pool.deposit(posKey, ZERO, ZERO, THREE, ZERO, ONE);
    }

    function test_ticks_ReturnExpectedValues() internal {
        deposit(1000 ether);

        IPoolInternal.TickWithLiquidity[] memory ticks = pool.ticks();

        assertEq(ticks[0].price, Pricing.MIN_TICK_PRICE);
        assertEq(ticks[1].price, posKey.lower);
        assertEq(ticks[2].price, posKey.upper);
        assertEq(ticks[3].price, Pricing.MAX_TICK_PRICE);

        assertEq(ticks[0].liquidityNet, ZERO);
        assertEq(ticks[1].liquidityNet, ud(1000 ether));
        assertEq(ticks[2].liquidityNet, ZERO);
        assertEq(ticks[3].liquidityNet, ZERO);
    }
}
