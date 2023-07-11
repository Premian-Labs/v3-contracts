// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolClaimTest is DeployTest {
    function _trade(uint256 size, bool isBuy) internal {
        vm.prank(users.trader);
        pool.trade(ud(size), isBuy, isBuy ? 10000e18 : 0, users.otherTrader);
    }

    function _setupPoolHistory() internal {
        deal(getPoolToken(), users.trader, 100000000e18);
        vm.prank(users.trader);
        IERC20(getPoolToken()).approve(address(router), 100000000e18);

        pool.mint(users.lp, PoolStorage.LONG, ud(1000e18));
        pool.mint(users.lp, PoolStorage.SHORT, ud(1000e18));

        posKey.lower = ud(0.05e18);
        posKey.upper = ud(0.55e18);
        posKey.orderType = Position.OrderType.CS;
        deposit(1e18);

        posKey.lower = ud(0.01e18);
        posKey.upper = ud(0.03e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(1e18);

        _trade(1e18, true);
        _trade(1e18, false);
        _trade(1e18, true);
        _trade(1e18, false);

        posKey.lower = ud(0.03e18);
        posKey.upper = ud(0.05e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(1e18);

        posKey.lower = ud(0.041e18);
        posKey.upper = ud(0.049e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(1e18);
        deposit(1e18);
        deposit(1e18);

        _trade(1e18, true);

        vm.warp(block.timestamp + 60);
        posKey.lower = ud(0.03e18);
        posKey.upper = ud(0.05e18);
        posKey.orderType = Position.OrderType.LC;
        vm.prank(users.lp);
        pool.withdraw(posKey, ud(1e18), ud(0), ud(1e18));

        _trade(1e18, false);

        posKey.lower = ud(0.041e18);
        posKey.upper = ud(0.049e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(0.05e18);

        _trade(1e18, true);

        posKey.lower = ud(0.499e18);
        posKey.upper = ud(0.549e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(2e18);

        _trade(2e18, false);
        _trade(1e18, false);

        posKey.lower = ud(0.041e18);
        posKey.upper = ud(0.049e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(88e18);

        _trade(1e18, true);
        _trade(1e18, true);
        _trade(1e18, true);

        posKey.lower = ud(0.551e18);
        posKey.upper = ud(0.651e18);
        posKey.orderType = Position.OrderType.CS;
        deposit(1e18);

        posKey.lower = ud(0.449e18);
        posKey.upper = ud(0.549e18);
        posKey.orderType = Position.OrderType.LC;
        deposit(1e18);
    }

    function test_claim_ClaimFees() public {
        uint256 tradeSize = 1 ether;
        (uint256 initialCollateral, uint256 totalPremium) = trade(tradeSize, true);

        uint256 claimableFees = pool.getClaimableFees(posKey);
        uint256 protocolFees = pool.protocolFees();
        IERC20 poolToken = IERC20(getPoolToken());

        vm.prank(users.lp);
        pool.claim(posKey);

        uint256 collateral = toTokenDecimals(contractsToCollateral(ud(tradeSize)));

        assertEq(poolToken.balanceOf(posKey.operator), initialCollateral - collateral + claimableFees);
        assertEq(poolToken.balanceOf(address(pool)), collateral + totalPremium - claimableFees - protocolFees);
        assertEq(poolToken.balanceOf(FEE_RECEIVER), protocolFees);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_claim_ClaimFees_2() public {
        _setupPoolHistory();

        uint256[] memory tokenIds = pool.tokensByAccount(users.lp);
        uint256 totalClaimableFees = 0;
        uint256 protocolFees = pool.protocolFees();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            if (tokenId == 0 || tokenId == 1) continue;

            (, , UD60x18 lower, UD60x18 upper, Position.OrderType orderType) = PoolStorage.parseTokenId(tokenId);

            Position.Key memory key = Position.Key(users.lp, users.lp, lower, upper, orderType);

            totalClaimableFees += pool.claim(key);
        }

        assertApproxEqAbs(totalClaimableFees, protocolFees, 10);
    }

    function test_getClaimableFees_ReturnExpectedValue() public {
        uint256 tradeSize = 1 ether;
        trade(tradeSize, true);

        UD60x18 price = posKey.lower;
        UD60x18 nextPrice = posKey.upper;
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(users.trader, ud(tradeSize), toTokenDecimals(ud(tradeSize) * avgPrice), true);

        assertEq(pool.getClaimableFees(posKey), takerFee / 2); // 50% protocol fee percentage
    }

    function test_getClaimableFees_ReturnExpectedValue_2() public {
        _setupPoolHistory();

        uint256[] memory tokenIds = pool.tokensByAccount(users.lp);
        uint256 totalClaimableFees = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];

            if (tokenId == 0 || tokenId == 1) continue;

            (, , UD60x18 lower, UD60x18 upper, Position.OrderType orderType) = PoolStorage.parseTokenId(tokenId);

            Position.Key memory key = Position.Key(users.lp, users.lp, lower, upper, orderType);

            totalClaimableFees += pool.getClaimableFees(key);
        }

        assertApproxEqAbs(totalClaimableFees, pool.protocolFees(), 10);
    }
}
