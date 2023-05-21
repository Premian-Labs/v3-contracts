// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ERC20Permit} from "@solidstate/contracts/token/ERC20/permit/ERC20Permit.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";

import {DeployTest} from "../Deploy.t.sol";

import {IPremiaStaking} from "contracts/staking/IPremiaStaking.sol";
import {PremiaStakingStorage} from "contracts/staking/PremiaStakingStorage.sol";
import {PremiaStakingMock} from "contracts/test/staking/PremiaStakingMock.sol";
import {PremiaStakingProxyMock} from "contracts/test/staking/PremiaStakingProxyMock.sol";

import {IOFT} from "contracts/layerZero/token/oft/IOFT.sol";

contract PremiaStakingTest is DeployTest {
    uint256 internal aliceId;
    address internal alice;
    address internal bob;
    address internal carol;

    uint256 internal stakeAmount = 120000e18;

    PremiaStakingMock internal premiaStaking;
    PremiaStakingMock internal otherPremiaStaking;

    address internal usdc;

    function setUp() public override {
        super.setUp();
        aliceId = 11;
        alice = vm.addr(aliceId);
        bob = vm.addr(12);
        carol = vm.addr(13);
        usdc = quote;

        address premiaStakingImplementation = address(
            new PremiaStakingMock(
                address(0),
                address(premia),
                address(usdc),
                address(exchangeHelper)
            )
        );

        address premiaStakingProxy = address(
            new PremiaStakingProxyMock(premiaStakingImplementation)
        );
        address otherPremiaStakingProxy = address(
            new PremiaStakingProxyMock(premiaStakingImplementation)
        );

        premiaStaking = PremiaStakingMock(premiaStakingProxy);
        otherPremiaStaking = PremiaStakingMock(otherPremiaStakingProxy);

        deal(usdc, address(this), 1000e6);
        IERC20(usdc).approve(address(premiaStaking), type(uint256).max);

        deal(address(premia), bob, 100 ether);
        deal(address(premia), carol, 100 ether);

        deal(address(premia), alice, stakeAmount);
        vm.prank(alice);
        premia.approve(address(premiaStaking), type(uint256).max);
    }

    function bridge(
        address fromUser,
        PremiaStakingMock premiaStaking,
        PremiaStakingMock otherPremiaStaking,
        address user,
        uint256 amount,
        uint64 stakePeriod,
        uint64 lockedUntil
    ) internal {
        vm.prank(fromUser);

        // Mocked bridge out
        premiaStaking.sendFrom(
            user,
            0,
            abi.encode(user),
            amount,
            payable(user),
            address(0),
            ""
        );

        // Mocked bridge in
        otherPremiaStaking.creditTo(user, amount, stakePeriod, lockedUntil);
    }

    function sign(
        uint256 signerId,
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("Premia")),
                keccak256(bytes("1")),
                chainId,
                address(premia)
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(signerId, hash);
    }

    function test_getTotalVotingPower_ReturnExpectedValue() public {
        assertEq(premiaStaking.getTotalPower(), 0);

        vm.startPrank(alice);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(1e18, 365 days);
        vm.stopPrank();

        assertEq(premiaStaking.getTotalPower(), 1.25e18);

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(3e18, 365 days / 2);

        assertEq(premiaStaking.getTotalPower(), 3.5e18);
    }

    function test_getUserVotingPower_ReturnExpectedValue() public {
        assertEq(premiaStaking.getTotalPower(), 0);

        vm.startPrank(alice);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(1e18, 365 days);
        vm.stopPrank();

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(3e18, 365 days / 2);

        assertEq(premiaStaking.getUserPower(alice), 1.25e18);
        assertEq(premiaStaking.getUserPower(bob), 2.25e18);
    }

    function test_StakeAndCalculateDiscountCorrectly() public {
        vm.startPrank(alice);

        premiaStaking.stake(stakeAmount, 365 days);
        assertEq(premiaStaking.getUserPower(alice), 150000e18);
        assertApproxEqAbs(
            premiaStaking.getDiscount(alice),
            0.2722e18,
            0.0001e18
        );

        vm.warp(block.timestamp + 365 days + 1);

        premiaStaking.startWithdraw(10000e18);
        assertEq(premiaStaking.getUserPower(alice), 137500e18);
        assertApproxEqAbs(
            premiaStaking.getDiscount(alice),
            0.2694e18,
            0.0001e18
        );

        deal(address(premia), alice, 5000000e18);
        premiaStaking.stake(5000000e18, 365 days);

        assertApproxEqAbs(premiaStaking.getDiscount(alice), 0.6e18, 0.0001e18);
    }

    function test_StakeWithPermitSuccessfully() public {
        vm.startPrank(alice);

        uint256 deadline = block.timestamp + 3600;

        (uint8 v, bytes32 r, bytes32 s) = sign(
            aliceId,
            alice,
            address(premiaStaking),
            stakeAmount,
            IERC2612(address(premia)).nonces(alice),
            deadline
        );
        premiaStaking.stakeWithPermit(stakeAmount, 365 days, deadline, v, r, s);

        assertEq(premiaStaking.getUserPower(alice), 150000e18);
    }

    function test_RevertIf_UnstakingWhenStakeIsLocked() public {
        vm.startPrank(alice);

        premiaStaking.stake(stakeAmount, 30 days);
        vm.expectRevert(IPremiaStaking.PremiaStaking__StakeLocked.selector);
        premiaStaking.startWithdraw(1);
    }

    function test_CalculateStakePeriodMultiplier() public {
        vm.startPrank(alice);

        assertEq(premiaStaking.getStakePeriodMultiplier(0), 0.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(365 days / 2), 0.75e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(365 days), 1.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(2 * 365 days), 2.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(4 * 365 days), 4.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(5 * 365 days), 4.25e18);
    }

    function test_FailTransferringTokens() public {
        vm.startPrank(alice);

        premiaStaking.stake(stakeAmount, 0);

        vm.expectRevert(IPremiaStaking.PremiaStaking__CantTransfer.selector);
        premiaStaking.transfer(bob, 1);
    }

    function test_RevertIf_NotEnoughAllowance() public {
        vm.startPrank(alice);

        premia.approve(address(premiaStaking), 0);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        premiaStaking.stake(100e18, 0);

        premia.approve(address(premiaStaking), 50e18);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        premiaStaking.stake(100e18, 0);

        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(100e18, 0);

        assertEq(premiaStaking.balanceOf(alice), 100e18);
    }

    function test_OnlyWithdrawWhatIsAvailable() public {
        vm.startPrank(alice);

        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(100e18, 0);

        vm.stopPrank();

        vm.startPrank(bob);

        premia.approve(address(otherPremiaStaking), 40e18);
        otherPremiaStaking.stake(20e18, 0);

        vm.stopPrank();

        bridge(alice, premiaStaking, otherPremiaStaking, alice, 50e18, 0, 0);

        vm.startPrank(alice);
        premiaStaking.startWithdraw(50e18);
        otherPremiaStaking.startWithdraw(10e18);
        vm.stopPrank();

        vm.prank(bob);
        otherPremiaStaking.startWithdraw(5e18);

        vm.expectRevert(
            IPremiaStaking.PremiaStaking__NotEnoughLiquidity.selector
        );
        vm.prank(alice);
        otherPremiaStaking.startWithdraw(10e18);
    }

    function test_HandleWithdrawalDelayCorrectly() public {
        vm.startPrank(alice);
        deal(address(premia), alice, 100e18); // Override Alice balance
        premiaStaking.stake(100e18, 0);

        vm.expectRevert(
            IPremiaStaking.PremiaStaking__NoPendingWithdrawal.selector
        );
        premiaStaking.withdraw();

        premiaStaking.startWithdraw(40e18);
        assertEq(premiaStaking.getAvailablePremiaAmount(), 60e18);

        vm.warp(block.timestamp + 10 days - 5);

        vm.expectRevert(
            IPremiaStaking.PremiaStaking__WithdrawalStillPending.selector
        );
        premiaStaking.withdraw();

        vm.warp(block.timestamp + 10);

        premiaStaking.withdraw();
        assertEq(premiaStaking.balanceOf(alice), 60e18);
        assertEq(premia.balanceOf(alice), 40e18);

        vm.expectRevert(
            IPremiaStaking.PremiaStaking__NoPendingWithdrawal.selector
        );
        premiaStaking.withdraw();
    }

    function test_DistributePartialRewardsProperly() public {
        deal(address(premia), alice, 100e18); // Override Alice balance

        vm.prank(alice);
        premiaStaking.stake(30e18, 0);

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        vm.startPrank(carol);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        assertEq(premiaStaking.balanceOf(alice), 30e18);
        assertEq(premiaStaking.balanceOf(bob), 10e18);
        assertEq(premiaStaking.balanceOf(carol), 10e18);
        assertEq(premia.balanceOf(address(premiaStaking)), 50e18);

        vm.prank(bob);
        premiaStaking.startWithdraw(10e18);

        // PremiaStaking get 50 USDC rewards
        premiaStaking.addRewards(50e6);

        (uint256 bobPendingWithdrawal, , ) = premiaStaking.getPendingWithdrawal(
            bob
        );

        assertEq(bobPendingWithdrawal, 10e18);

        vm.warp(block.timestamp + 30 days);

        uint256 pendingRewards = premiaStaking.getPendingRewards();

        (uint256 carolRewards, ) = premiaStaking.getPendingUserRewards(carol);

        assertEq(carolRewards, (pendingRewards * 10) / 40);
    }

    function test_WorkAsExpected_WithMultipleParticipants() public {
        deal(address(premia), alice, 100e18); // Override Alice balance
        vm.prank(alice);
        premiaStaking.stake(30e18, 0);

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        vm.startPrank(carol);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        assertEq(premiaStaking.balanceOf(alice), 30e18);
        assertEq(premiaStaking.balanceOf(bob), 10e18);
        assertEq(premiaStaking.balanceOf(carol), 10e18);
        assertEq(premia.balanceOf(address(premiaStaking)), 50e18);

        premiaStaking.addRewards(50e6);

        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 30 days);

        uint256 pendingRewards1 = premiaStaking.getPendingRewards();
        (uint256 availableRewards, uint256 unstakeRewards) = premiaStaking
            .getAvailableRewards();

        uint256 decayValue = premiaStaking.decay(
            50e6,
            timestamp,
            timestamp + 30 days
        );

        assertEq(pendingRewards1, 50e6 - decayValue);
        assertEq(availableRewards, 50e6 - (50e6 - decayValue));
        assertEq(unstakeRewards, 0);

        (uint256 alicePendingRewards, ) = premiaStaking.getPendingUserRewards(
            alice
        );
        (uint256 bobPendingRewards, ) = premiaStaking.getPendingUserRewards(
            bob
        );
        (uint256 carolPendingRewards, ) = premiaStaking.getPendingUserRewards(
            carol
        );

        assertEq(alicePendingRewards, (pendingRewards1 * 30) / 50);
        assertEq(bobPendingRewards, (pendingRewards1 * 10) / 50);
        assertEq(carolPendingRewards, (pendingRewards1 * 10) / 50);

        vm.warp(block.timestamp + 300000 days);

        (alicePendingRewards, ) = premiaStaking.getPendingUserRewards(alice);
        (bobPendingRewards, ) = premiaStaking.getPendingUserRewards(bob);
        (carolPendingRewards, ) = premiaStaking.getPendingUserRewards(carol);

        assertEq(alicePendingRewards, (50e6 * 30) / 50);
        assertEq(bobPendingRewards, (50e6 * 10) / 50);
        assertEq(carolPendingRewards, (50e6 * 10) / 50);

        vm.prank(bob);
        premiaStaking.stake(50e18, 0);

        assertEq(premiaStaking.balanceOf(alice), 30e18);
        assertEq(premiaStaking.balanceOf(bob), 60e18);
        assertEq(premiaStaking.balanceOf(carol), 10e18);

        vm.prank(alice);
        premiaStaking.startWithdraw(5e18);
        vm.prank(bob);
        premiaStaking.startWithdraw(20e18);

        assertEq(premiaStaking.balanceOf(alice), 25e18);
        assertEq(premiaStaking.balanceOf(bob), 40e18);
        assertEq(premiaStaking.balanceOf(carol), 10e18);

        // Pending withdrawals should not count anymore as staked
        premiaStaking.addRewards(100e6);
        timestamp = block.timestamp;

        vm.warp(timestamp + 30 days);

        uint256 pendingRewards2 = premiaStaking.getPendingRewards();
        (availableRewards, unstakeRewards) = premiaStaking
            .getAvailableRewards();
        decayValue = premiaStaking.decay(100e6, timestamp, timestamp + 30 days);

        assertEq(pendingRewards2, 100e6 - decayValue);
        assertEq(availableRewards, 100e6 - (100e6 - decayValue));
        assertEq(unstakeRewards, 0);

        (alicePendingRewards, ) = premiaStaking.getPendingUserRewards(alice);
        (bobPendingRewards, ) = premiaStaking.getPendingUserRewards(bob);
        (carolPendingRewards, ) = premiaStaking.getPendingUserRewards(carol);

        assertEq(
            alicePendingRewards,
            (50e6 * 30) / 50 + (pendingRewards2 * 25) / 75
        );
        assertEq(
            bobPendingRewards,
            (50e6 * 10) / 50 + (pendingRewards2 * 40) / 75
        );
        assertEq(
            carolPendingRewards,
            (50e6 * 10) / 50 + (pendingRewards2 * 10) / 75
        );

        vm.warp(block.timestamp + 300000 days);

        vm.prank(alice);
        premiaStaking.withdraw();
        vm.prank(bob);
        premiaStaking.withdraw();

        // Alice = 100 - 30 + 5
        assertEq(premia.balanceOf(alice), 75e18);
        // Bob = 100 - 10 - 50 + 20
        assertEq(premia.balanceOf(bob), 60e18);

        vm.prank(alice);
        premiaStaking.startWithdraw(25e18);
        vm.prank(bob);
        premiaStaking.startWithdraw(40e18);
        vm.prank(carol);
        premiaStaking.startWithdraw(10e18);

        vm.warp(block.timestamp + 10 days + 1);

        vm.prank(alice);
        premiaStaking.withdraw();
        vm.prank(bob);
        premiaStaking.withdraw();
        vm.prank(carol);
        premiaStaking.withdraw();

        assertEq(premiaStaking.totalSupply(), 0);
        assertEq(premia.balanceOf(alice), 100e18);
        assertEq(premia.balanceOf(bob), 100e18);
        assertEq(premia.balanceOf(carol), 100e18);

        (alicePendingRewards, ) = premiaStaking.getPendingUserRewards(alice);
        (bobPendingRewards, ) = premiaStaking.getPendingUserRewards(bob);
        (carolPendingRewards, ) = premiaStaking.getPendingUserRewards(carol);

        // Note : Doesnt compile without the uint256 casts
        assertEq(
            alicePendingRewards,
            (50e6 * 30) / 50 + uint256(100e6 * 25) / 75
        );
        assertEq(
            bobPendingRewards,
            (50e6 * 10) / 50 + uint256(100e6 * 40) / 75
        );
        assertEq(
            carolPendingRewards,
            (50e6 * 10) / 50 + uint256(100e6 * 10) / 75
        );
    }

    function test_decay_ReturnExpectedValue() public {
        assertEq(
            premiaStaking.decay(100e18, 0, 30 days),
            49.666471687219732700e18
        );
        assertEq(
            premiaStaking.decay(100e18, 0, 60 days),
            24.667584098573993300e18
        );
    }

    function test_BridgeToOtherContract() public {
        deal(address(premia), alice, 100e18); // Override Alice balance
        vm.startPrank(alice);
        premiaStaking.stake(100e18, 365 days);
        premiaStaking.approve(address(premiaStaking), 100e18);
        vm.stopPrank();

        assertEq(premiaStaking.totalSupply(), 100e18);
        assertEq(otherPremiaStaking.totalSupply(), 0);

        bridge(alice, premiaStaking, otherPremiaStaking, alice, 10e18, 0, 0);

        assertEq(premia.balanceOf(address(premiaStaking)), 100e18);
        assertEq(premia.balanceOf(address(otherPremiaStaking)), 0);
        assertEq(premiaStaking.totalSupply(), 90e18);
        assertEq(otherPremiaStaking.totalSupply(), 10e18);
    }

    function test_getStakeLevels_ReturnExpectedValue() public {
        IPremiaStaking.StakeLevel[] memory stakeLevels = premiaStaking
            .getStakeLevels();
        assertEq(stakeLevels.length, 4);
        assertEq(stakeLevels[0].amount, 5000e18);
        assertEq(stakeLevels[0].discount, 0.1e18);
        assertEq(stakeLevels[1].amount, 50000e18);
        assertEq(stakeLevels[1].discount, 0.25e18);
        assertEq(stakeLevels[2].amount, 500000e18);
        assertEq(stakeLevels[2].discount, 0.35e18);
        assertEq(stakeLevels[3].amount, 2500000e18);
        assertEq(stakeLevels[3].discount, 0.6e18);
    }

    function test_harvest_Success() public {
        deal(address(premia), alice, 100e18); // Override Alice balance
        vm.prank(alice);
        premiaStaking.stake(30e18, 0);

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        vm.startPrank(carol);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(10e18, 0);
        vm.stopPrank();

        premiaStaking.addRewards(50e6);

        vm.warp(block.timestamp + 30 days);

        (uint256 alicePendingRewards, ) = premiaStaking.getPendingUserRewards(
            alice
        );

        vm.prank(alice);
        premiaStaking.harvest();

        assertEq(IERC20(usdc).balanceOf(alice), alicePendingRewards);
        (alicePendingRewards, ) = premiaStaking.getPendingUserRewards(alice);
        assertEq(alicePendingRewards, 0);
    }

    function test_earlyUnstake_Success() public {
        deal(address(premia), alice, 100e18); // Override Alice balance

        vm.prank(alice);
        premiaStaking.stake(100e18, 4 * 365 days);

        vm.startPrank(bob);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(50e18, 365 days);
        vm.stopPrank();

        vm.startPrank(carol);
        premia.approve(address(premiaStaking), 100e18);
        premiaStaking.stake(100e18, 365 days);
        vm.stopPrank();

        //

        assertEq(premiaStaking.getEarlyUnstakeFee(alice), 0.75e18);
        vm.warp(block.timestamp + 2 * 365 days);
        assertEq(premiaStaking.getEarlyUnstakeFee(alice), 0.5e18);

        vm.prank(alice);
        premiaStaking.earlyUnstake(100e18);

        (uint256 alicePendingWithdrawal, , ) = premiaStaking
            .getPendingWithdrawal(alice);

        assertEq(alicePendingWithdrawal, 50e18);

        // Note : Does not compile without the uint256 casts
        uint256 bobFeeReward = uint256(50e18) / 3;
        uint256 carolFeeReward = uint256(50e18 * 2) / 3;

        (, uint256 bobUnstakeRewards) = premiaStaking.getPendingUserRewards(
            bob
        );
        (, uint256 carolUnstakeRewards) = premiaStaking.getPendingUserRewards(
            carol
        );
        assertEq(bobUnstakeRewards, bobFeeReward);
        assertEq(carolUnstakeRewards, carolFeeReward);

        vm.prank(bob);
        premiaStaking.harvest();
        assertEq(premiaStaking.balanceOf(bob), 50e18 + bobFeeReward);

        vm.prank(carol);
        premiaStaking.harvest();
        assertEq(premiaStaking.balanceOf(carol), 100e18 + carolFeeReward);
    }

    function test_updateLock_Success() public {
        vm.startPrank(alice);

        premiaStaking.stake(1000, 0);

        PremiaStakingStorage.UserInfo memory uInfo = premiaStaking.getUserInfo(
            alice
        );
        assertEq(uInfo.stakePeriod, 0);
        assertEq(uInfo.lockedUntil, block.timestamp);
        assertEq(premiaStaking.getUserPower(alice), 250);
        assertEq(premiaStaking.getTotalPower(), 250);

        premiaStaking.updateLock(2 * 365 days);

        uInfo = premiaStaking.getUserInfo(alice);
        assertEq(uInfo.stakePeriod, 2 * 365 days);
        assertEq(uInfo.lockedUntil, block.timestamp + 2 * 365 days);
        assertEq(premiaStaking.getUserPower(alice), 2250);
        assertEq(premiaStaking.getTotalPower(), 2250);
    }

    function test_getDiscount_ReturnExpectedValue() public {
        uint256 amount = 10000e18;

        vm.startPrank(alice);
        premiaStaking.stake(amount, 2.5 * 365 days);

        // Period multiplier of x2.75
        assertEq(
            premiaStaking.getStakePeriodMultiplier(2.5 * 365 days),
            2.75e18
        );

        // Total power of 10000 * 2.75 = 27500
        assertEq(premiaStaking.getUserPower(alice), 27500e18);

        // 27500 is halfway between first and second stake level -> 5000 + ((50 000 - 5000) / 2) = 27500
        // Therefore expected discount is halfway between first and second discount level -> 0.1 + ((0.25 - 0.1) / 2) = 0.175
        assertEq(premiaStaking.getDiscount(alice), 0.175e18);
    }

    function test_getDiscountBPS_ReturnExpectedValue() public {
        uint256 amount = 10000e18;

        vm.startPrank(alice);
        premiaStaking.stake(amount, 2.5 * 365 days);

        // Period multiplier of x2.75
        assertEq(
            premiaStaking.getStakePeriodMultiplier(2.5 * 365 days),
            2.75e18
        );

        // Total power of 10000 * 2.75 = 27500
        assertEq(premiaStaking.getUserPower(alice), 27500e18);

        // 27500 is halfway between first and second stake level -> 5000 + ((50 000 - 5000) / 2) = 27500
        // Therefore expected discount is halfway between first and second discount level -> 0.1 + ((0.25 - 0.1) / 2) = 0.175
        assertEq(premiaStaking.getDiscountBPS(alice), 1750);
    }

    function test_getStakePeriodMultiplier_ReturnExpectedValue() public {
        assertEq(premiaStaking.getStakePeriodMultiplier(0), 0.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(365 days), 1.25e18);
        assertEq(
            premiaStaking.getStakePeriodMultiplier(1.5 * 365 days),
            1.75e18
        );
        assertEq(premiaStaking.getStakePeriodMultiplier(3 * 365 days), 3.25e18);
        assertEq(premiaStaking.getStakePeriodMultiplier(5 * 365 days), 4.25e18);
    }

    function test_getStakePeriodMultiplierBPS_ReturnExpectedValue() public {
        assertEq(premiaStaking.getStakePeriodMultiplierBPS(0), 2500);
        assertEq(premiaStaking.getStakePeriodMultiplierBPS(365 days), 12500);
        assertEq(
            premiaStaking.getStakePeriodMultiplierBPS(1.5 * 365 days),
            17500
        );
        assertEq(
            premiaStaking.getStakePeriodMultiplierBPS(3 * 365 days),
            32500
        );
        assertEq(
            premiaStaking.getStakePeriodMultiplierBPS(5 * 365 days),
            42500
        );
    }

    function test_getEarlyUnstakeFee_ReturnExpectedValue() public {
        vm.prank(alice);
        premiaStaking.stake(1000, 4 * 365 days);

        assertEq(premiaStaking.getEarlyUnstakeFee(alice), 0.75e18);

        vm.warp(block.timestamp + 2 * 365 days);

        assertEq(premiaStaking.getEarlyUnstakeFee(alice), 0.5e18);
    }

    function test_getEarlyUnstakeFeeBPS_ReturnExpectedValue() public {
        vm.prank(alice);
        premiaStaking.stake(1000, 4 * 365 days);

        assertEq(premiaStaking.getEarlyUnstakeFeeBPS(alice), 7500);

        vm.warp(block.timestamp + 2 * 365 days);

        assertEq(premiaStaking.getEarlyUnstakeFeeBPS(alice), 5000);
    }

    function test_sendFrom_Success_IfNoApprovalButOwner() public {
        vm.startPrank(alice);
        premiaStaking.stake(1, 0);

        premiaStaking.sendFrom(
            alice,
            0,
            abi.encode(alice),
            1,
            payable(alice),
            address(0),
            ""
        );
    }

    function test_sendFrom_RevertIf_NotApprovedNotOwner() public {
        vm.startPrank(alice);

        vm.expectRevert(IOFT.OFT_InsufficientAllowance.selector);

        premiaStaking.sendFrom(
            address(premiaStaking),
            0,
            abi.encode(alice),
            1,
            payable(alice),
            address(0),
            ""
        );
    }
}
