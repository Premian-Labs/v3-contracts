// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IDualMining} from "contracts/mining/dualMining/IDualMining.sol";
import {DualMining} from "contracts/mining/dualMining/DualMining.sol";
import {DualMiningProxy} from "contracts/mining/dualMining/DualMiningProxy.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {VaultMiningSetup} from "../vaultMining/VaultMining.setup.t.sol";

contract DualMiningTest is VaultMiningSetup {
    DualMining internal dualMining;
    ERC20Mock internal rewardToken;

    function setUp() public override {
        super.setUp();

        rewardToken = new ERC20Mock("REWARD", 18);
        UD60x18 rewardsPerYear = ud(365 * 25e18); // 10x less than vaultMining rewards rate
        DualMining implementation = new DualMining(address(vaultMining));
        DualMiningProxy proxy = new DualMiningProxy(
            address(implementation),
            address(vaultA),
            address(rewardToken),
            rewardsPerYear
        );

        dualMining = DualMining(address(proxy));
    }

    function _addRewards() internal {
        vm.startPrank(alice);
        rewardToken.mint(alice, 1_000e18);
        rewardToken.approve(address(dualMining), 1_000e18);
        dualMining.addRewards(ud(1_000e18));
        vm.stopPrank();
    }

    event Initialized(address indexed caller, UD60x18 initialParentAccRewardsPerShare, uint256 timestamp);

    function test_init_Success() public {
        _addRewards();

        vm.expectEmit();
        emit Initialized(address(vaultMining), ud(1e18), block.timestamp);

        vm.prank(address(vaultMining));
        dualMining.init(ud(1e18));
    }

    function test_init_ThroughVaultMining_Success() public {
        _addRewards();

        vm.expectEmit();
        emit Initialized(address(vaultMining), ud(0), block.timestamp);

        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));
    }

    function test_init_RevertIf_NoMiningRewards() public {
        vm.prank(alice);
        vm.expectRevert(IDualMining.DualMining__NoMiningRewards.selector);
        dualMining.init(ud(1e18));
    }

    function test_init_RevertIf_NotVaultMining() public {
        _addRewards();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDualMining.DualMining__NotAuthorized.selector, alice));
        dualMining.init(ud(1e18));
    }

    function test_init_RevertIf_AlreadyInitialized() public {
        _addRewards();

        vm.prank(address(vaultMining));
        dualMining.init(ud(1e18));
    }

    function test_addRewards_Success() public {
        _addRewards();
        assertEq(dualMining.getRewardsAvailable(), 1_000e18);
    }

    function test_addRewards_RevertIf_MiningEnded() public {
        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        vaultA.mint(alice, 10e18);
        vm.warp(10000 * ONE_DAY);
        vaultA.mint(alice, 10e18);

        vm.startPrank(alice);
        rewardToken.mint(alice, 1_000e18);
        rewardToken.approve(address(dualMining), 1_000e18);

        vm.expectRevert(IDualMining.DualMining__MiningEnded.selector);
        dualMining.addRewards(ud(1_000e18));
    }

    function test_updatePool_RevertIf_NotVaultMining() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDualMining.DualMining__NotAuthorized.selector, alice));
        dualMining.updatePool(ud(1e18), ud(1e18));
    }

    function test_updatePool_RevertIf_NotInitialized() public {
        vm.prank(address(vaultMining));
        vm.expectRevert(IDualMining.DualMining__NotInitialized.selector);
        dualMining.updatePool(ud(1e18), ud(1e18));
    }

    function test_updateUser_RevertIf_NotVaultMining() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDualMining.DualMining__NotAuthorized.selector, alice));
        dualMining.updateUser(alice, ud(1e18), ud(1e18), ud(1e18), ud(1e18), ud(1e18));
    }

    function test_updateUser_RevertIf_NotInitialized() public {
        vm.prank(address(vaultMining));
        vm.expectRevert(IDualMining.DualMining__NotInitialized.selector);
        dualMining.updateUser(alice, ud(1e18), ud(1e18), ud(1e18), ud(1e18), ud(1e18));
    }

    function test_claim_RevertIf_NotInitialized() public {
        vm.expectRevert(IDualMining.DualMining__NotInitialized.selector);

        vm.prank(address(vaultMining));
        dualMining.claim(alice);
    }

    function test_claim_RevertIf_NotVaultMining() public {
        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDualMining.DualMining__NotAuthorized.selector, alice));
        dualMining.claim(alice);
    }

    // This test follows `test_vaultMining_DistributeRewardsCorrectly` in `VaultMining.t.sol`
    function test_dualMining_DistributeRewardsCorrectly() public {
        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        // Precision used in assertions
        uint256 delta = 1e6;

        uint256 ts = block.timestamp;

        vaultB.mint(alice, 10e18);

        vm.warp(ts + ONE_DAY);
        vaultA.mint(alice, 10e18);

        vm.warp(ts + 3 * ONE_DAY);
        vaultA.mint(bob, 20e18);

        // Alice should have 2 * 25 pending reward now
        assertApproxEqAbs(dualMining.getPendingUserRewards(alice).unwrap(), 50e18, delta, "a");

        vm.warp(ts + 6 * ONE_DAY);
        vaultA.mint(carol, 30e18);

        vm.warp(ts + 8 * ONE_DAY);
        vaultA.mint(alice, 10e18);

        // Alice should have pending reward of : 2*25 + 3*1/3*25 + 2*1/6*25 = 83.3333333333333
        assertApproxEqAbs(dualMining.getPendingUserRewards(alice).unwrap(), 83.3333333333333e18, delta);

        // Bob should have pending reward of: 3*2/3*25 + 2*2/6*25 + 5*2/7*25 = 102.38095238095239
        vm.warp(ts + 13 * ONE_DAY);
        vaultA.burn(bob, 5e18);

        assertApproxEqAbs(dualMining.getPendingUserRewards(bob).unwrap(), 102.38095238095239e18, delta);

        vm.warp(ts + 14 * ONE_DAY);
        vaultA.burn(alice, 20e18);

        vm.warp(ts + 15 * ONE_DAY);
        vaultA.burn(bob, 15e18);

        vm.warp(ts + 16 * ONE_DAY);
        vaultA.burn(carol, 30e18);

        // 25 per day emission
        assertApproxEqAbs(dualMining.getRewardsAvailable().unwrap(), 1_000e18 - (16 * 25e18), delta);

        // Alice should have: 83.33333333333333 + 5*2/7*25 + 1*2/6.5*25 = 126.73992673992673
        assertApproxEqAbs(dualMining.getPendingUserRewards(alice).unwrap(), 126.73992673992673e18, delta);

        // Bob should have: 102.38095238095239 + 1*1.5/6.5 * 25 + 1*1.5/4.5*25 = 116.48351648351647
        assertApproxEqAbs(dualMining.getPendingUserRewards(bob).unwrap(), 116.48351648351647e18, delta);

        // Carol should have: 2*3/6*25 + 5*3/7*25 + 1*3/6.5*25 + 1*3/4.5*25 + 1*25 = 131.77655677655678
        assertApproxEqAbs(dualMining.getPendingUserRewards(carol).unwrap(), 131.77655677655678e18, delta);

        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        vm.prank(alice);
        vaultMining.claimAll(vaultList);

        vm.prank(bob);
        vaultMining.claimAll(vaultList);

        vm.prank(carol);
        vaultMining.claimAll(vaultList);

        assertApproxEqAbs(rewardToken.balanceOf(alice), 126.73992673992673e18, delta);
        assertApproxEqAbs(rewardToken.balanceOf(bob), 116.48351648351647e18, delta);
        assertApproxEqAbs(rewardToken.balanceOf(carol), 131.77655677655678e18, delta);
    }

    function test_dualMining_StopDistributingRewards_IfRewardsRunOut() public {
        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vm.warp(ts + 10000 * ONE_DAY);
        assertEq(dualMining.getPendingUserRewards(alice), 1_000e18);

        assertEq(rewardToken.balanceOf(address(dualMining)), 1_000e18);

        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        vm.prank(alice);
        vaultMining.claimAll(vaultList);
        assertEq(dualMining.getPendingUserRewards(alice), 0);
        assertEq(rewardToken.balanceOf(alice), 1_000e18);
        assertEq(rewardToken.balanceOf(address(dualMining)), 0);

        vm.warp(block.timestamp + ONE_DAY);
        assertEq(dualMining.getPendingUserRewards(alice), 0);
    }

    // This tests that when first update is triggered for a user, we dont count the accumulated rewards in parent contract,
    // from last user update until start of dualMining.
    function test_dualMining_ProperlySubtract_OnFirstUserUpdate() public {
        // Precision used in assertions
        uint256 delta = 1e6;

        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vm.warp(ts + 2 * ONE_DAY);

        assertApproxEqAbs(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)).unwrap(), 500e18, delta);

        vaultA.mint(bob, 20e18);
        vm.warp(ts + 3 * ONE_DAY);

        // 500 + (1 * 250 / 3) = 583.3333333333334
        assertApproxEqAbs(
            vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)).unwrap(),
            583.3333333333334e18,
            delta
        );
        // 2 * 250 / 3 = 166.66666666666666
        assertApproxEqAbs(
            vaultMining.getPendingUserRewardsFromVault(bob, address(vaultA)).unwrap(),
            166.66666666666666e18,
            delta
        );

        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        assertEq(dualMining.getPendingUserRewards(alice).unwrap(), 0);
        assertEq(dualMining.getPendingUserRewards(bob).unwrap(), 0);

        vm.warp(ts + 4 * ONE_DAY);
        vaultA.mint(carol, 30e18);

        // 1 * 25 / 3 = 8.333333333333334
        assertApproxEqAbs(dualMining.getPendingUserRewards(alice).unwrap(), 8.333333333333334e18, delta);
        // 2 * 25 / 3 = 16.666666666666668
        assertApproxEqAbs(dualMining.getPendingUserRewards(bob).unwrap(), 16.666666666666668e18, delta);
        assertApproxEqAbs(dualMining.getPendingUserRewards(carol).unwrap(), 0, delta);

        vm.warp(ts + 6 * ONE_DAY);

        // 8.333333333333334 + 2 * (1 * 25 / 6) = 16.666666666666668
        assertApproxEqAbs(dualMining.getPendingUserRewards(alice).unwrap(), 16.666666666666668e18, delta);
        // 16.666666666666668 + 2 * (2 * 25 / 6) = 33.333333333333336
        assertApproxEqAbs(dualMining.getPendingUserRewards(bob).unwrap(), 33.333333333333336e18, delta);
        // 2 * (3 * 25 / 6) = 25
        assertApproxEqAbs(dualMining.getPendingUserRewards(carol).unwrap(), 25e18, delta);
    }

    // This tests that when last update is triggered for a user, we dont count the accumulated rewards in parent contract,
    // from end of dualMining until now
    function test_dualMining_ProperlySubtract_OnLastUserUpdate() public {
        // Precision used in assertions
        uint256 delta = 1e6;

        uint256 ts = block.timestamp;

        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        _addRewards();
        vm.prank(admin);
        vaultMining.addDualMiningPool(address(vaultA), address(dualMining));

        vaultA.mint(alice, 10e18);
        vaultA.mint(bob, 20e18);
        vaultA.mint(carol, 30e18);

        vm.warp(ts + 10 * ONE_DAY);
        vm.prank(alice);
        vaultMining.claimAll(vaultList);

        vm.warp(ts + 20 * ONE_DAY);
        vm.prank(bob);
        vaultMining.claimAll(vaultList);

        vm.warp(ts + 100 * ONE_DAY);

        vm.prank(alice);
        vaultMining.claimAll(vaultList);

        vm.warp(ts + 300 * ONE_DAY);

        assertApproxEqAbs(
            rewardToken.balanceOf(alice) + dualMining.getPendingUserRewards(alice).unwrap(),
            (1 * 1_000e18) / uint256(6),
            delta
        );
        assertApproxEqAbs(
            rewardToken.balanceOf(bob) + dualMining.getPendingUserRewards(bob).unwrap(),
            (2 * 1_000e18) / uint256(6),
            delta
        );
        assertApproxEqAbs(dualMining.getPendingUserRewards(carol).unwrap(), (3 * 1_000e18) / uint256(6), delta);

        vm.prank(alice);
        vaultMining.claimAll(vaultList);

        vm.prank(bob);
        vaultMining.claimAll(vaultList);

        vm.prank(carol);
        vaultMining.claimAll(vaultList);

        assertApproxEqAbs(rewardToken.balanceOf(address(dualMining)), 0, delta);
        assertEq(dualMining.getRewardsAvailable().unwrap(), 0);

        assertApproxEqAbs(rewardToken.balanceOf(alice), (1 * 1_000e18) / uint256(6), delta, "alice");
        assertApproxEqAbs(rewardToken.balanceOf(bob), (2 * 1_000e18) / uint256(6), delta, "bob");
        assertApproxEqAbs(rewardToken.balanceOf(carol), (3 * 1_000e18) / uint256(6), delta, "carol");
    }
}
