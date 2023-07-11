// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {IVaultMining} from "contracts/mining/vaultMining/IVaultMining.sol";

import {VaultMiningSetup} from "./VaultMining.setup.t.sol";

contract ProxyManagerMock {
    function getPoolList() external pure returns (address[] memory poolList) {
        return poolList;
    }
}

contract VaultMiningTest is VaultMiningSetup {
    function test_vaultMining_UpdateShares_OnMintAndBurn() public {
        assertEq(vaultMining.getVaultInfo(address(vaultA)).totalShares, 0);
        assertEq(vaultMining.getUserInfo(alice, address(vaultA)).shares, 0);

        vaultA.mint(alice, 100e18);

        assertEq(vaultMining.getVaultInfo(address(vaultA)).totalShares, 100e18);
        assertEq(vaultMining.getUserInfo(alice, address(vaultA)).shares, 100e18);
        assertEq(vaultMining.getUserInfo(bob, address(vaultA)).shares, 0);

        vaultA.mint(bob, 30e18);

        assertEq(vaultMining.getVaultInfo(address(vaultA)).totalShares, 130e18);
        assertEq(vaultMining.getUserInfo(alice, address(vaultA)).shares, 100e18);
        assertEq(vaultMining.getUserInfo(bob, address(vaultA)).shares, 30e18);

        vaultA.burn(alice, 40e18);

        assertEq(vaultMining.getVaultInfo(address(vaultA)).totalShares, 90e18);
        assertEq(vaultMining.getUserInfo(alice, address(vaultA)).shares, 60e18);
        assertEq(vaultMining.getUserInfo(bob, address(vaultA)).shares, 30e18);
    }

    function test_vaultMining_RevertIf_NotRegisteredVault() public {
        vm.expectRevert(
            abi.encodeWithSelector(IVaultMining.VaultMining__NotVault.selector, address(vaultNotRegistered))
        );

        vaultNotRegistered.mint(alice, 100e18);
    }

    function test_updateUser_RevertIf_NotRegisteredVault() public {
        vm.expectRevert(abi.encodeWithSelector(IVaultMining.VaultMining__NotVault.selector, bob));
        vm.prank(bob);
        vaultMining.updateUser(address(alice), alice, ud(1000e18), ud(1000e18), ud(1e18));
    }

    function test_vaultMining_DistributeRewardsCorrectly() public {
        // Precision used in assertions
        uint256 delta = 1e6;

        uint256 ts = block.timestamp;

        vaultB.mint(alice, 10e18);

        vm.warp(ts + ONE_DAY);
        vaultA.mint(alice, 10e18);

        vm.warp(ts + 3 * ONE_DAY);
        vaultA.mint(bob, 20e18);

        // There is 4 vaults with equal alloc points, with premia reward of 1k per day
        // Each pool should get 250 reward per day. Lp1 should therefore have 2 * 250 pending reward now
        assertApproxEqAbs(vaultMining.getPendingUserRewards(alice, address(vaultA)).unwrap(), 500e18, delta);

        vm.warp(ts + 6 * ONE_DAY);
        vaultA.mint(carol, 30e18);

        vm.warp(ts + 8 * ONE_DAY);
        vaultA.mint(alice, 10e18);

        // Alice should have pending reward of : 2*250 + 3*1/3*250 + 2*1/6*250 = 833.3333333333333
        assertApproxEqAbs(
            vaultMining.getPendingUserRewards(alice, address(vaultA)).unwrap(),
            833.3333333333333e18,
            delta
        );

        // Bob should have pending reward of: 3*2/3*250 + 2*2/6*250 + 5*2/7*250 = 1023.8095238095239
        vm.warp(ts + 13 * ONE_DAY);
        vaultA.burn(bob, 5e18);

        assertApproxEqAbs(
            vaultMining.getPendingUserRewards(bob, address(vaultA)).unwrap(),
            1023.8095238095239e18,
            delta
        );

        vm.warp(ts + 14 * ONE_DAY);
        vaultA.burn(alice, 20e18);

        vm.warp(ts + 15 * ONE_DAY);
        vaultA.burn(bob, 15e18);

        vm.warp(ts + 16 * ONE_DAY);
        vaultA.burn(carol, 30e18);

        // 1k per day emission, but 3 pools didnt had update yet allocating pending rewards, so only 15k/4 already allocated
        assertApproxEqAbs(vaultMining.getRewardsAvailable().unwrap(), 200_000e18 - 15_000e18 / 4, delta);

        // Alice should have: 833.3333333333333 + 5*2/7*250 + 1*2/6.5*250 = 1267.3992673992673
        assertApproxEqAbs(
            vaultMining.getPendingUserRewards(alice, address(vaultA)).unwrap(),
            1267.3992673992673e18,
            delta
        );

        // Bob should have: 1023.8095238095239 + 1*1.5/6.5 * 250 + 1*1.5/4.5*250 = 1164.8351648351647
        assertApproxEqAbs(
            vaultMining.getPendingUserRewards(bob, address(vaultA)).unwrap(),
            1164.8351648351647e18,
            delta
        );

        // Carol should have: 2*3/6*250 + 5*3/7*250 + 1*3/6.5*250 + 1*3/4.5*250 + 1*250 = 1317.7655677655678
        assertApproxEqAbs(
            vaultMining.getPendingUserRewards(carol, address(vaultA)).unwrap(),
            1317.7655677655678e18,
            delta
        );

        assertApproxEqAbs(vaultMining.getPendingUserRewards(alice, address(vaultB)).unwrap(), 4000e18, delta);

        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        vm.prank(alice);
        vaultMining.claim(vaultList);

        vm.prank(bob);
        vaultMining.claim(vaultList);

        vm.prank(carol);
        vaultMining.claim(vaultList);

        assertApproxEqAbs(optionReward.balanceOf(alice, 0), 1267.3992673992673e18, delta);
        assertApproxEqAbs(optionReward.balanceOf(bob, 0), 1164.8351648351647e18, delta);
        assertApproxEqAbs(optionReward.balanceOf(carol, 0), 1317.7655677655678e18, delta);
    }

    function test_vaultMining_StopDistributingRewards_IfRewardsRunOut() public {
        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vm.warp(ts + 4 * 200 * ONE_DAY + ONE_DAY);
        assertEq(vaultMining.getPendingUserRewards(alice, address(vaultA)), 200_000e18);

        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        vm.prank(alice);
        vaultMining.claim(vaultList);
        assertEq(vaultMining.getPendingUserRewards(alice, address(vaultA)), 0);
        assertEq(optionReward.balanceOf(alice, 0), 200_000e18);

        vm.warp(block.timestamp + ONE_DAY);
        assertEq(vaultMining.getPendingUserRewards(alice, address(vaultA)), 0);

        vaultMining.updateVault(address(vaultA));
        vm.prank(admin);
        vaultMining.addRewards(ud(200_000e18));

        vm.warp(block.timestamp + ONE_DAY);
        assertApproxEqAbs(vaultMining.getPendingUserRewards(alice, address(vaultA)).unwrap(), 250e18, 1e6);
    }

    function test_setRewardsPerYear_UpdateRewardsPerYear() public {
        vm.prank(admin);
        vaultMining.setRewardsPerYear(ud(1000e18));
        assertEq(vaultMining.getRewardsPerYear(), 1000e18);
    }

    function test_setRewardsPerYear_RevertIf_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vaultMining.setRewardsPerYear(ud(1000e18));
    }
}
