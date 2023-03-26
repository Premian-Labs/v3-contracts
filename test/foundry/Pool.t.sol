// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {DeployTest} from "./Deploy.t.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";

import {IPool} from "contracts/pool/IPool.sol";
import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";

contract PoolTest is DeployTest {
    IPool callPool;
    IPool putPool;

    function setUp() public override {
        super.setUp();

        callPool = IPool(factory.deployPool{value: 1 ether}(poolKey));
        poolKey.isCallPool = false;
        putPool = IPool(factory.deployPool{value: 1 ether}(poolKey));
        poolKey.isCallPool = true;
    }

    function _test_deposit(bool isCall) internal {
        poolKey.isCallPool = isCall;
        IPool pool = isCall ? callPool : putPool;

        vm.startPrank(lp);

        ERC20Mock token = ERC20Mock(getPoolToken(isCall));
        uint256 _initialCollateral = initialCollateral(isCall).unwrap();

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

        UD60x18 avgPrice = posKey.lower.avg(posKey.upper);
        UD60x18 collateral = contractsToCollateral(depositSize, isCall);
        uint256 collateralValue = scaleDecimals(collateral * avgPrice, isCall);

        assertEq(pool.balanceOf(lp, tokenId()), depositSize);
        assertEq(pool.totalSupply(tokenId()), depositSize);
        assertEq(token.balanceOf(address(pool)), collateralValue);
        assertEq(token.balanceOf(lp), _initialCollateral - collateralValue);
        assertEq(pool.marketPrice(), posKey.upper);
    }

    function test_deposit_1000_LC_CALL() public {
        _test_deposit(true);
    }

    function test_deposit_1000_LC_PUT() public {
        _test_deposit(false);
    }
}
