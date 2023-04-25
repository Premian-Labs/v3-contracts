// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Permit2} from "contracts/libraries/Permit2.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolDepositTest is DeployTest {
    function _test_deposit_1000_LC_WithToken(bool isCall) internal {
        poolKey.isCallPool = isCall;

        IERC20 token = IERC20(getPoolToken(isCall));
        UD60x18 depositSize = UD60x18.wrap(1000 ether);
        uint256 initialCollateral = deposit(depositSize);

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(
            token.balanceOf(users.lp),
            initialCollateral - collateralValue
        );
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_1000_LC_WithToken() public {
        _test_deposit_1000_LC_WithToken(poolKey.isCallPool);
    }

    function test_deposit_RevertIf_SenderNotOperator() public {
        posKey.operator = users.trader;

        vm.prank(users.lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__NotAuthorized.selector,
                users.lp
            )
        );

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function _test_deposit_RevertIf_MarketPriceOutOfMinMax(
        bool isCall
    ) internal {
        poolKey.isCallPool = isCall;
        deposit(1000 ether);
        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        UD60x18 minPrice = posKey.upper + UD60x18.wrap(1);
        UD60x18 maxPrice = posKey.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                posKey.upper,
                minPrice,
                maxPrice
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            minPrice,
            maxPrice,
            Permit2.emptyPermit()
        );

        minPrice = posKey.upper - UD60x18.wrap(10);
        maxPrice = posKey.upper - UD60x18.wrap(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                posKey.upper,
                minPrice,
                maxPrice
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            minPrice,
            maxPrice,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_RevertIf_MarketPriceOutOfMinMax() public {
        _test_deposit_RevertIf_MarketPriceOutOfMinMax(poolKey.isCallPool);
    }

    function test_deposit_RevertIf_ZeroSize() public {
        vm.prank(users.lp);
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            ZERO,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_RevertIf_Expired() public {
        vm.prank(users.lp);

        vm.warp(poolKey.maturity + 1);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);

        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_RevertIf_InvalidRange() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ZERO;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = UD60x18.wrap(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(1.01e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }

    function test_deposit_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = UD60x18.wrap(0.2501e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TickWidthInvalid.selector,
                posKey.lower
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );

        posKey.lower = posKeySave.lower;
        posKey.upper = UD60x18.wrap(0.7501e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TickWidthInvalid.selector,
                posKey.upper
            )
        );
        pool.deposit(
            posKey,
            ZERO,
            ZERO,
            THREE,
            ZERO,
            ONE,
            Permit2.emptyPermit()
        );
    }
}
