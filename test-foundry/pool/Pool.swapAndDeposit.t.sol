// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/Console.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";
import {ZERO, ONE_HALF, ONE, TWO, THREE} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";
import {IPool} from "contracts/pool/IPool.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolSwapAndDepositTest is DeployTest {
    function _test_swapAndDeposit_Success(bool isCall) internal {
        address swapToken = getSwapToken(isCall);
        address poolToken = getPoolToken(isCall);

        vm.startPrank(users.lp);

        UD60x18 depositSize = THREE;

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        (uint256 swapQuote, , , ) = IQuoterV2(uniswapQuoter)
            .quoteExactOutputSingle(
                IQuoterV2.QuoteExactOutputSingleParams({
                    tokenIn: swapToken,
                    tokenOut: poolToken,
                    amount: collateralValue,
                    fee: 3000,
                    sqrtPriceLimitX96: 0
                })
            );

        deal(swapToken, users.lp, swapQuote);

        IERC20(swapToken).approve(address(router), type(uint256).max);

        bytes memory data = abi.encodePacked(
            bytes4(
                keccak256(
                    "exactOutputSingle((address,address,uint24,address,uint256,uint256,uint160))"
                )
            ),
            abi.encode(
                swapToken,
                poolToken,
                3000,
                address(exchangeHelper),
                collateralValue,
                swapQuote,
                0
            )
        );

        IPoolInternal.SwapArgs memory swapArgs = IPoolInternal.SwapArgs({
            tokenIn: swapToken,
            tokenOut: poolToken,
            amountInMax: swapQuote,
            amountOutMin: collateralValue,
            callee: address(uniswapRouter),
            allowanceTarget: address(uniswapRouter),
            data: data,
            refundAddress: users.lp
        });

        (UD60x18 nearestBelowLower, UD60x18 nearestBelowUpper) = pool
            .getNearestTicksBelow(posKey.lower, posKey.upper);

        pool.swapAndDeposit(
            swapArgs,
            posKey,
            nearestBelowLower,
            nearestBelowUpper,
            THREE,
            ZERO,
            ONE
        );

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize,
            "pool balance"
        );
        assertEq(pool.totalSupply(tokenId()), depositSize, "pool total supply");
        assertEq(
            IERC20(poolToken).balanceOf(address(pool)),
            collateralValue,
            "pool token balance"
        );
        assertEq(
            IERC20(swapToken).balanceOf(address(users.lp)),
            0,
            "swap token balance"
        );
        assertEq(IERC20(poolToken).balanceOf(users.lp), 0, "lp token balance");
        assertEq(pool.marketPrice(), posKey.upper, "market price");
    }

    function test_swapAndDeposit_Success() public {
        _test_swapAndDeposit_Success(poolKey.isCallPool);
    }
}
