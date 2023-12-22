// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {IERC20BaseInternal} from "@solidstate/contracts/token/ERC20/base/IERC20BaseInternal.sol";

import {ERC20Mock} from "../token/ERC20Mock.sol";
import {RewardDistributor, IRewardDistributor} from "contracts/utils/RewardDistributor.sol";

contract RewardDistributorTest is Test {
    ERC20Mock internal token;
    RewardDistributor internal rewardDistributor;

    address internal rewardProvider;
    address internal alice;
    address internal bob;
    address internal carol;

    function setUp() public {
        token = new ERC20Mock("TEST", 18);

        rewardDistributor = new RewardDistributor(address(token));

        rewardProvider = address(0x1);
        alice = address(0x2);
        bob = address(0x3);
        carol = address(0x4);

        deal(address(token), rewardProvider, 300e18);
        vm.prank(rewardProvider);
        token.approve(address(rewardDistributor), 300e18);
    }

    function addRewards() internal {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 50e18;
        amounts[1] = 150e18;
        amounts[2] = 100e18;

        vm.prank(rewardProvider);
        rewardDistributor.addRewards(users, amounts);
    }

    function test_addRewards_Success() external {
        addRewards();

        assertEq(token.balanceOf(address(rewardDistributor)), 300e18);
        assertEq(token.balanceOf(address(rewardProvider)), 0);
        assertEq(rewardDistributor.rewards(alice), 50e18);
        assertEq(rewardDistributor.rewards(bob), 150e18);
        assertEq(rewardDistributor.rewards(carol), 100e18);
    }

    function test_addRewards_RevertIf_InvalidArrayLength() external {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 50e18;
        amounts[1] = 150e18;

        vm.prank(rewardProvider);
        vm.expectRevert(IRewardDistributor.RewardDistributor__InvalidArrayLength.selector);
        rewardDistributor.addRewards(users, amounts);
    }

    function test_addRewards_NotEnoughTokens() external {
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 50e18;
        amounts[1] = 150e18;
        amounts[2] = 101e18;

        vm.startPrank(rewardProvider);
        token.approve(address(rewardDistributor), 301e18);
        vm.expectRevert(IERC20BaseInternal.ERC20Base__TransferExceedsBalance.selector);
        rewardDistributor.addRewards(users, amounts);
    }

    function test_claim_Success() external {
        addRewards();

        vm.prank(alice);
        rewardDistributor.claim();
        assertEq(token.balanceOf(alice), 50e18);
        assertEq(rewardDistributor.rewards(alice), 0);
        assertEq(token.balanceOf(address(rewardDistributor)), 250e18);

        vm.prank(bob);
        rewardDistributor.claim();
        assertEq(token.balanceOf(bob), 150e18);
        assertEq(rewardDistributor.rewards(bob), 0);
        assertEq(token.balanceOf(address(rewardDistributor)), 100e18);

        vm.prank(carol);
        rewardDistributor.claim();
        assertEq(token.balanceOf(carol), 100e18);
        assertEq(rewardDistributor.rewards(carol), 0);
        assertEq(token.balanceOf(address(rewardDistributor)), 0);
    }

    function test_claim_NoRewards() external {
        vm.prank(alice);
        vm.expectRevert(IRewardDistributor.RewardDistributor__NoRewards.selector);
        rewardDistributor.claim();

        addRewards();

        vm.expectRevert(IRewardDistributor.RewardDistributor__NoRewards.selector);
        rewardDistributor.claim();

        vm.startPrank(alice);
        rewardDistributor.claim();
        vm.expectRevert(IRewardDistributor.RewardDistributor__NoRewards.selector);
        rewardDistributor.claim();
    }
}
