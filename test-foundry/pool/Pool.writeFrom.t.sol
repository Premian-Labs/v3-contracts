// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Position} from "contracts/libraries/Position.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolWriteFromTest is DeployTest {
    function _mintForLP(bool isCall) internal returns (uint256) {
        IERC20 poolToken = IERC20(getPoolToken(isCall));

        uint256 initialCollateral = scaleDecimals(
            contractsToCollateral(
                isCall ? ud(1000 ether) : ud(1000 ether) * poolKey.strike,
                isCall
            ),
            isCall
        );

        deal(address(poolToken), users.lp, initialCollateral);
        vm.prank(users.lp);
        poolToken.approve(address(router), initialCollateral);

        return initialCollateral;
    }

    function _test_writeFrom_Write_500_Options(bool isCall) internal {
        uint256 initialCollateral = _mintForLP(isCall);

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, size);

        uint256 collateral = scaleDecimals(
            contractsToCollateral(size, isCall),
            isCall
        ) + fee;

        IERC20 poolToken = IERC20(getPoolToken(isCall));

        assertEq(poolToken.balanceOf(address(pool)), collateral);
        assertEq(poolToken.balanceOf(users.lp), initialCollateral - collateral);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }

    function test_writeFrom_Write_500_Options() public {
        _test_writeFrom_Write_500_Options(poolKey.isCallPool);
    }

    function _test_writeFrom_Write_500_Options_OnBehalfOfAnotherAddress(
        bool isCall
    ) internal {
        uint256 initialCollateral = _mintForLP(isCall);

        UD60x18 size = ud(500 ether);
        uint256 fee = pool.takerFee(users.trader, size, 0, true);

        vm.prank(users.lp);
        pool.setApprovalForAll(users.otherTrader, true);

        vm.prank(users.otherTrader);
        pool.writeFrom(users.lp, users.trader, size);

        uint256 collateral = scaleDecimals(
            contractsToCollateral(size, isCall),
            isCall
        ) + fee;

        IERC20 poolToken = IERC20(getPoolToken(isCall));

        assertEq(poolToken.balanceOf(address(pool)), collateral);
        assertEq(poolToken.balanceOf(users.lp), initialCollateral - collateral);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), size);
        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.LONG), 0);
        assertEq(pool.balanceOf(users.lp, PoolStorage.SHORT), size);
    }

    function test_writeFrom_Write_500_Options_OnBehalfOfAnotherAddress()
        public
    {
        _test_writeFrom_Write_500_Options_OnBehalfOfAnotherAddress(
            poolKey.isCallPool
        );
    }

    function test_writeFrom_RevertIf_OnBehalfOfAnotherAddress_WithoutApproval()
        public
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OperatorNotAuthorized.selector,
                users.otherTrader
            )
        );
        vm.prank(users.otherTrader);
        pool.writeFrom(users.lp, users.trader, ud(500 ether));
    }

    function test_writeFrom_RevertIf_SizeIsZero() public {
        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, ud(0));
    }

    function test_writeFrom_RevertIf_OptionIsExpired() public {
        vm.warp(poolKey.maturity);
        vm.expectRevert(IPoolInternal.Pool__OptionExpired.selector);
        vm.prank(users.lp);
        pool.writeFrom(users.lp, users.trader, ud(500 ether));
    }
}
