// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Position} from "contracts/libraries/Position.sol";

import {IPoolEvents} from "contracts/pool/IPoolEvents.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolWriteFromTest is DeployTest {
    function _mintForLP() internal returns (uint256) {
        IERC20 poolToken = IERC20(getPoolToken());

        uint256 initialCollateral = scaleDecimals(
            contractsToCollateral(isCallTest ? ud(1000 ether) : ud(1000 ether) * poolKey.strike)
        );

        deal(address(poolToken), users.lp, initialCollateral);
        vm.prank(users.lp);
        poolToken.approve(address(router), initialCollateral);

        return initialCollateral;
    }

    function test_writeFrom_Write_500_Options() public {
        uint256 initialCollateral = _mintForLP();

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, size, address(0));

        uint256 collateral = scaleDecimals(contractsToCollateral(size)) + fee;

        IERC20 poolToken = IERC20(getPoolToken());

        assertEq(poolToken.balanceOf(address(pool)), collateral);
        assertEq(poolToken.balanceOf(users.lp), initialCollateral - collateral);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }

    function test_writeFrom_Write_500_Options_WithReferral() internal {
        uint256 initialCollateral = _mintForLP();

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, size, users.referrer);

        uint256 totalRebate;

        {
            (UD60x18 primaryRebatePercent, UD60x18 secondaryRebatePercent) = referral.getRebatePercents(users.referrer);

            UD60x18 _primaryRebate = primaryRebatePercent * scaleDecimals(fee);

            UD60x18 _secondaryRebate = secondaryRebatePercent * scaleDecimals(fee);

            uint256 primaryRebate = scaleDecimals(_primaryRebate);
            uint256 secondaryRebate = scaleDecimals(_secondaryRebate);

            totalRebate = primaryRebate + secondaryRebate;
        }

        uint256 collateral = scaleDecimals(contractsToCollateral(size));

        IERC20 poolToken = IERC20(getPoolToken());

        assertEq(poolToken.balanceOf(address(referral)), totalRebate);

        assertEq(poolToken.balanceOf(address(pool)), collateral + fee - totalRebate);
        assertEq(poolToken.balanceOf(users.lp), initialCollateral - collateral - fee);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);

        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }

    function test_writeFrom_Write_500_Options_OnBehalfOfAnotherAddress() public {
        uint256 initialCollateral = _mintForLP();

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        setActionAuthorization(users.lp, IUserSettings.Action.WRITE_FROM, true);

        vm.prank(users.operator);
        pool.writeFrom(users.lp, users.trader, size, address(0));

        uint256 collateral = scaleDecimals(contractsToCollateral(size)) + fee;

        IERC20 poolToken = IERC20(getPoolToken());

        assertEq(poolToken.balanceOf(address(pool)), collateral);
        assertEq(poolToken.balanceOf(users.lp), initialCollateral - collateral);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        address indexed taker,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 protocolFee
    );

    function test_writeFrom_UseUnderwriterAsTaker() public {
        _mintForLP();

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        vm.expectEmit();

        emit WriteFrom(users.lp, users.trader, users.lp, size, contractsToCollateral(size), ud(scaleDecimalsTo(fee)));

        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, size, address(0));
    }

    function test_writeFrom_RevertIf_OperatorNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.operator));
        vm.prank(users.operator);
        pool.writeFrom(users.lp, users.trader, ud(500 ether), address(0));
    }

    function test_writeFrom_RevertIf_SizeIsZero() public {
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, ud(0), address(0));
    }

    function test_writeFrom_RevertIf_OptionIsExpired() public {
        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, ud(500 ether), address(0));
    }
}
