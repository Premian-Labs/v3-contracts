// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {VxPremiaStorage} from "contracts/staking/VxPremiaStorage.sol";
import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";

import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

contract PoolListMock {
    function getPoolList() external pure returns (address[] memory poolList) {
        poolList = new address[](3);
        poolList[0] = 0x000004354F938CF1aCC2414B68951ad7a8730fB6;
        poolList[1] = 0x100004354f938cf1acc2414B68951aD7A8730fb6;
        poolList[2] = 0x200004354F938cf1ACc2414b68951ad7A8730Fb6;
    }
}

contract VxPremiaTest is Test {
    address internal alice;
    address internal bob;

    VxPremia internal vxPremia;
    ERC20Mock internal premia;
    ERC20Mock internal usdc;

    address internal pool0;
    address internal pool1;
    address internal pool2;

    event RemoveVote(address indexed voter, VxPremiaStorage.VoteVersion indexed version, bytes target, uint256 amount);

    function setUp() public {
        alice = vm.addr(1);
        bob = vm.addr(2);

        pool0 = 0x000004354F938CF1aCC2414B68951ad7a8730fB6;
        pool1 = 0x100004354f938cf1acc2414B68951aD7A8730fb6;
        pool2 = 0x200004354F938cf1ACc2414b68951ad7A8730Fb6;

        premia = new ERC20Mock("PREMIA", 18);
        usdc = new ERC20Mock("USDC", 6);

        address poolListMock = address(new PoolListMock());

        address vxPremiaImpl = address(
            new VxPremia(poolListMock, address(0), address(premia), address(usdc), address(0))
        );

        address vxPremiaProxy = address(new VxPremiaProxy(vxPremiaImpl));

        vxPremia = VxPremia(vxPremiaProxy);

        deal(address(premia), alice, 100e18);
        deal(address(premia), bob, 100e18);
        vm.prank(alice);
        premia.approve(address(vxPremia), type(uint256).max);
        vm.prank(bob);
        premia.approve(address(vxPremia), type(uint256).max);
    }

    function test_getUserVotes_ReturnExpectedValue() public {
        vm.startPrank(alice);
        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](3);
        votes[0].amount = 1e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 10e18;
        votes[1].target = abi.encodePacked(pool1, true);
        votes[2].amount = 1.5e18;
        votes[2].target = abi.encodePacked(pool1, false);

        vxPremia.castVotes(votes);

        VxPremiaStorage.Vote[] memory userVotes = vxPremia.getUserVotes(alice);

        assertEq(userVotes.length, 3);
        assertEq(userVotes[0].amount, 1e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool0, true));
        assertEq(userVotes[1].amount, 10e18);
        assertEq(userVotes[1].target, abi.encodePacked(pool1, true));
        assertEq(userVotes[2].amount, 1.5e18);
        assertEq(userVotes[2].target, abi.encodePacked(pool1, false));
    }

    function test_castVotes_Success() public {
        vm.startPrank(alice);
        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](3);
        votes[0].amount = 1e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 10e18;
        votes[1].target = abi.encodePacked(pool1, true);
        votes[2].amount = 1.5e18;
        votes[2].target = abi.encodePacked(pool1, false);

        vxPremia.castVotes(votes);

        VxPremiaStorage.Vote[] memory userVotes = vxPremia.getUserVotes(alice);

        assertEq(userVotes.length, 3);
        assertEq(userVotes[0].amount, 1e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool0, true));
        assertEq(userVotes[1].amount, 10e18);
        assertEq(userVotes[1].target, abi.encodePacked(pool1, true));
        assertEq(userVotes[2].amount, 1.5e18);
        assertEq(userVotes[2].target, abi.encodePacked(pool1, false));

        // Casting new votes should remove all existing votes, and set new ones

        votes = new VxPremiaStorage.Vote[](1);
        votes[0].amount = 2e18;
        votes[0].target = abi.encodePacked(pool2, false);

        vxPremia.castVotes(votes);

        userVotes = vxPremia.getUserVotes(alice);

        assertEq(userVotes.length, 1);
        assertEq(userVotes[0].amount, 2e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool2, false));

        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool0, false)), 0);
        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool0, true)), 0);
        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool1, false)), 0);
        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool1, true)), 0);
        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool2, false)), 2e18);
        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool2, true)), 0);
    }

    function test_castVotes_RevertIf_NotEnoughVotingPower() public {
        vm.startPrank(alice);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](1);
        votes[0].amount = 1e18;
        votes[0].target = abi.encodePacked(pool0, true);

        vm.expectRevert(IVxPremia.VxPremia__NotEnoughVotingPower.selector);
        vxPremia.castVotes(votes);

        vxPremia.stake(1e18, 365 days);
        votes[0].amount = 10e18;

        vm.expectRevert(IVxPremia.VxPremia__NotEnoughVotingPower.selector);
        vxPremia.castVotes(votes);
    }

    function test_RemoveSomeVotes_IfSomeTokensWithdrawn() public {
        vm.startPrank(alice);

        vxPremia.stake(5e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](3);
        votes[0].amount = 1e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 3e18;
        votes[1].target = abi.encodePacked(pool1, true);
        votes[2].amount = 2.25e18;
        votes[2].target = abi.encodePacked(pool1, false);

        vxPremia.castVotes(votes);

        vm.warp(block.timestamp + 366 days);

        VxPremiaStorage.Vote[] memory userVotes = vxPremia.getUserVotes(alice);

        assertEq(userVotes.length, 3);
        assertEq(userVotes[0].amount, 1e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool0, true));
        assertEq(userVotes[1].amount, 3e18);
        assertEq(userVotes[1].target, abi.encodePacked(pool1, true));
        assertEq(userVotes[2].amount, 2.25e18);
        assertEq(userVotes[2].target, abi.encodePacked(pool1, false));
        assertEq(vxPremia.getUserPower(alice), 6.25e18);

        vxPremia.startWithdraw(2.5e18);

        userVotes = vxPremia.getUserVotes(alice);

        assertEq(userVotes.length, 2);
        assertEq(userVotes[0].amount, 1e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool0, true));
        assertEq(userVotes[1].amount, 2.125e18);
        assertEq(userVotes[1].target, abi.encodePacked(pool1, true));
        assertEq(vxPremia.getUserPower(alice), 3.125e18);
    }

    function test_UpdateTotalPoolVotes() public {
        vm.startPrank(alice);

        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](1);
        votes[0].amount = 12.5e18;
        votes[0].target = abi.encodePacked(pool0, true);

        vxPremia.castVotes(votes);

        vm.warp(block.timestamp + 366 days);

        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool0, true)), 12.5e18);

        vxPremia.startWithdraw(5e18);

        assertEq(vxPremia.getPoolVotes(VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool0, true)), 6.25e18);
    }

    function test_RemoveAllVotes_IfUnstakingAll() public {
        vm.startPrank(alice);

        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](2);
        votes[0].amount = 6.25e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 6.25e18;
        votes[1].target = abi.encodePacked(pool1, true);

        vxPremia.castVotes(votes);

        vm.warp(block.timestamp + 366 days);

        assertEq(vxPremia.getUserVotes(alice).length, 2);

        vxPremia.startWithdraw(10e18);

        assertEq(vxPremia.getUserVotes(alice).length, 0);
    }

    function test_Emit_RemoveVote() public {
        vm.startPrank(alice);

        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](2);
        votes[0].amount = 7e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 3e18;
        votes[1].target = abi.encodePacked(pool1, true);

        vxPremia.castVotes(votes);

        vm.warp(block.timestamp + 366 days);

        vm.expectEmit(true, true, true, true, address(vxPremia));
        emit RemoveVote(alice, VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool1, true), 2.5e18);
        vxPremia.startWithdraw(4e18);

        vm.expectEmit(true, true, true, true, address(vxPremia));
        emit RemoveVote(alice, VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool1, true), 0.5e18);
        vm.expectEmit(true, true, true, true, address(vxPremia));
        emit RemoveVote(alice, VxPremiaStorage.VoteVersion.V2, abi.encodePacked(pool0, true), 4.5e18);
        vxPremia.startWithdraw(4e18);
    }

    function test_resetUserVotes_Success() public {
        vm.startPrank(alice);

        vxPremia.stake(10e18, 365 days);

        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](2);
        votes[0].amount = 7e18;
        votes[0].target = abi.encodePacked(pool0, true);
        votes[1].amount = 3e18;
        votes[1].target = abi.encodePacked(pool1, true);

        vxPremia.castVotes(votes);

        VxPremiaStorage.Vote[] memory userVotes = vxPremia.getUserVotes(alice);
        assertEq(userVotes.length, 2);
        assertEq(userVotes[0].amount, 7e18);
        assertEq(userVotes[0].target, abi.encodePacked(pool0, true));
        assertEq(userVotes[1].amount, 3e18);
        assertEq(userVotes[1].target, abi.encodePacked(pool1, true));

        vm.stopPrank();

        vxPremia.resetUserVotes(alice);

        userVotes = vxPremia.getUserVotes(alice);
        assertEq(userVotes.length, 0);
    }

    function test_resetUserVotes_RevertIf_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vxPremia.resetUserVotes(alice);
    }
}
