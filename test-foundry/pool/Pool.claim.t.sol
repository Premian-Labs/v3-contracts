// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {Position} from "contracts/libraries/Position.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolClaimTest is DeployTest {
    function test_claim_ClaimFees() public {
        uint256 tradeSize = 1 ether;
        (uint256 initialCollateral, uint256 totalPremium) = trade(
            tradeSize,
            isCallTest,
            true
        );

        uint256 claimableFees = pool.getClaimableFees(posKey);
        uint256 protocolFees = pool.protocolFees();
        IERC20 poolToken = IERC20(getPoolToken(isCallTest));

        vm.prank(users.lp);
        pool.claim(posKey);

        uint256 collateral = scaleDecimals(
            contractsToCollateral(ud(tradeSize), isCallTest),
            isCallTest
        );

        assertEq(
            poolToken.balanceOf(posKey.operator),
            initialCollateral - collateral + claimableFees
        );
        assertEq(
            poolToken.balanceOf(address(pool)),
            collateral + totalPremium - claimableFees - protocolFees
        );
        assertEq(poolToken.balanceOf(feeReceiver), protocolFees);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), tradeSize);
        assertEq(pool.balanceOf(address(pool), PoolStorage.SHORT), tradeSize);
    }

    function test_getClaimableFees_ReturnExpectedValue() public {
        uint256 tradeSize = 1 ether;
        trade(tradeSize, isCallTest, true);

        UD60x18 price = posKey.lower;
        UD60x18 nextPrice = posKey.upper;
        UD60x18 avgPrice = price.avg(nextPrice);

        uint256 takerFee = pool.takerFee(
            users.trader,
            ud(tradeSize),
            scaleDecimals(ud(tradeSize) * avgPrice, isCallTest),
            true
        );

        assertEq(pool.getClaimableFees(posKey), takerFee / 2); // 50% protocol fee percentage
    }
}
