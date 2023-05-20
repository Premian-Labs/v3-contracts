// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolWithdrawTest is DeployTest {
    function test_withdraw_750LC() public {
        UD60x18 depositSize = ud(1000 ether);
        uint256 initialCollateral = deposit(depositSize);
        vm.warp(block.timestamp + 60);

        uint256 depositCollateralValue = scaleDecimals(
            contractsToCollateral(ud(200 ether))
        );

        address poolToken = getPoolToken();

        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue
        );
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue
        );

        UD60x18 withdrawSize = ud(750 ether);
        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        uint256 withdrawCollateralValue = scaleDecimals(
            contractsToCollateral(withdrawSize * avgPrice)
        );

        vm.prank(users.lp);
        pool.withdraw(posKey, withdrawSize, ZERO, ONE);

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize - withdrawSize
        );
        assertEq(pool.totalSupply(tokenId()), depositSize - withdrawSize);
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            depositCollateralValue - withdrawCollateralValue
        );
        assertEq(
            IERC20(poolToken).balanceOf(users.lp),
            initialCollateral - depositCollateralValue + withdrawCollateralValue
        );
    }

    function test_withdraw_RevertIf_BeforeEndOfWithdrawalDelay() public {
        deposit(1000 ether);

        vm.warp(block.timestamp + 55);
        vm.prank(users.lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__WithdrawalDelayNotElapsed.selector,
                block.timestamp + 5
            )
        );

        pool.withdraw(posKey, ud(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_OperatorNotAuthorized() public {
        posKey.operator = users.trader;
        vm.prank(users.lp);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OperatorNotAuthorized.selector,
                users.lp
            )
        );
        pool.withdraw(posKey, ud(100 ether), ZERO, ONE);
    }

    function test_withdraw_RevertIf_MarketPriceOutOfMinMax() public {
        deposit(1000 ether);

        assertEq(pool.marketPrice(), posKey.upper);

        vm.startPrank(users.lp);

        UD60x18 minPrice = posKey.upper + ud(1);
        UD60x18 maxPrice = posKey.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                posKey.upper,
                minPrice,
                maxPrice
            )
        );
        pool.withdraw(posKey, THREE, minPrice, maxPrice);

        minPrice = posKey.upper - ud(10);
        maxPrice = posKey.upper - ud(1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__AboveMaxSlippage.selector,
                posKey.upper,
                minPrice,
                maxPrice
            )
        );
        pool.withdraw(posKey, THREE, minPrice, maxPrice);
    }

    function test_withdraw_RevertIf_ZeroSize() public {
        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.withdraw(posKey, ZERO, ZERO, ONE);
    }

    function test_withdraw_RevertIf_Expired() public {
        vm.startPrank(users.lp);

        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_NonExistingPosition() public {
        vm.startPrank(users.lp);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__PositionDoesNotExist.selector,
                posKey.owner,
                tokenId()
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidRange() public {
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
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ZERO;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = ONE_HALF;
        posKey.upper = ONE_HALF / TWO;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = ud(0.0001e18);
        posKey.upper = posKeySave.upper;
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(1.01e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__InvalidRange.selector,
                posKey.lower,
                posKey.upper
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }

    function test_withdraw_RevertIf_InvalidTickWidth() public {
        vm.startPrank(users.lp);

        Position.Key memory posKeySave = posKey;

        posKey.lower = ud(0.2501e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TickWidthInvalid.selector,
                posKey.lower
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);

        posKey.lower = posKeySave.lower;
        posKey.upper = ud(0.7501e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__TickWidthInvalid.selector,
                posKey.upper
            )
        );
        pool.withdraw(posKey, THREE, ZERO, ONE);
    }
}
