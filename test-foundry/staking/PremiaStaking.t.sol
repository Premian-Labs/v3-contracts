// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ERC20Permit} from "@solidstate/contracts/token/ERC20/permit/ERC20Permit.sol";
import {IERC2612} from "@solidstate/contracts/token/ERC20/permit/IERC2612.sol";

import {DeployTest} from "../Deploy.t.sol";

import {IPremiaStaking} from "contracts/staking/IPremiaStaking.sol";

contract PremiaStakingTest is DeployTest {
    uint256 aliceId;
    address alice;
    address bob;
    address carol;

    uint256 stakeAmount = 120000e18;

    function setUp() public override {
        super.setUp();
        aliceId = 11;
        alice = vm.addr(aliceId);
        bob = vm.addr(12);
        carol = vm.addr(13);

        deal(address(premia), alice, 100 ether);
        deal(address(premia), bob, 100 ether);
        deal(address(premia), carol, 100 ether);
    }

    function init() internal {
        deal(address(premia), alice, stakeAmount);
        vm.startPrank(alice);
        premia.approve(address(vxPremia), type(uint256).max);
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
        assertEq(vxPremia.getTotalPower(), 0);

        vm.startPrank(alice);
        premia.approve(address(vxPremia), 100e18);
        vxPremia.stake(1e18, 365 days);
        vm.stopPrank();

        assertEq(vxPremia.getTotalPower(), 1.25e18);

        vm.startPrank(bob);
        premia.approve(address(vxPremia), 100e18);
        vxPremia.stake(3e18, 365 days / 2);

        assertEq(vxPremia.getTotalPower(), 3.5e18);
    }

    function test_getUserVotingPower_ReturnExpectedValue() public {
        assertEq(vxPremia.getTotalPower(), 0);

        vm.startPrank(alice);
        premia.approve(address(vxPremia), 100e18);
        vxPremia.stake(1e18, 365 days);
        vm.stopPrank();

        vm.startPrank(bob);
        premia.approve(address(vxPremia), 100e18);
        vxPremia.stake(3e18, 365 days / 2);

        assertEq(vxPremia.getUserPower(alice), 1.25e18);
        assertEq(vxPremia.getUserPower(bob), 2.25e18);
    }

    function test_StakeAndCalculateDiscountCorrectly() public {
        init();

        vxPremia.stake(stakeAmount, 365 days);
        assertEq(vxPremia.getUserPower(alice), 150000e18);
        assertApproxEqAbs(vxPremia.getDiscount(alice), 0.2722e18, 0.0001e18);

        vm.warp(block.timestamp + 365 days + 1);

        vxPremia.startWithdraw(10000e18);
        assertEq(vxPremia.getUserPower(alice), 137500e18);
        assertApproxEqAbs(vxPremia.getDiscount(alice), 0.2694e18, 0.0001e18);

        deal(address(premia), alice, 5000000e18);
        vxPremia.stake(5000000e18, 365 days);

        assertApproxEqAbs(vxPremia.getDiscount(alice), 0.6e18, 0.0001e18);
    }

    function test_StakeWithPermitSuccessfully() public {
        init();

        uint256 deadline = block.timestamp + 3600;

        (uint8 v, bytes32 r, bytes32 s) = sign(
            aliceId,
            alice,
            address(vxPremia),
            stakeAmount,
            IERC2612(address(premia)).nonces(alice),
            deadline
        );
        vxPremia.stakeWithPermit(stakeAmount, 365 days, deadline, v, r, s);

        assertEq(vxPremia.getUserPower(alice), 150000e18);
    }

    function test_RevertIf_UnstakingWhenStakeIsLocked() public {
        init();

        vxPremia.stake(stakeAmount, 30 days);
        vm.expectRevert(IPremiaStaking.PremiaStaking__StakeLocked.selector);
        vxPremia.startWithdraw(1);
    }

    function test_CalculateStakePeriodMultiplier() public {
        init();

        assertEq(vxPremia.getStakePeriodMultiplier(0), 0.25e18);
        assertEq(vxPremia.getStakePeriodMultiplier(365 days / 2), 0.75e18);
        assertEq(vxPremia.getStakePeriodMultiplier(365 days), 1.25e18);
        assertEq(vxPremia.getStakePeriodMultiplier(2 * 365 days), 2.25e18);
        assertEq(vxPremia.getStakePeriodMultiplier(4 * 365 days), 4.25e18);
        assertEq(vxPremia.getStakePeriodMultiplier(5 * 365 days), 4.25e18);
    }

    function test_FailTransferringTokens() public {
        init();

        vxPremia.stake(stakeAmount, 0);

        vm.expectRevert(IPremiaStaking.PremiaStaking__CantTransfer.selector);
        vxPremia.transfer(bob, 1);
    }

    function test_RevertIf_NotEnoughAllowance() public {
        init();

        premia.approve(address(vxPremia), 0);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        vxPremia.stake(100e18, 0);

        premia.approve(address(vxPremia), 50e18);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        vxPremia.stake(100e18, 0);

        premia.approve(address(vxPremia), 100e18);
        vxPremia.stake(100e18, 0);

        assertEq(vxPremia.balanceOf(alice), 100e18);
    }
}
