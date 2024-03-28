// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {ZERO, ONE} from "contracts/libraries/Constants.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {IPremiaAirdrip} from "contracts/utils/IPremiaAirdrip.sol";
import {PremiaAirdrip} from "contracts/utils/PremiaAirdrip.sol";

import {ERC20Mock} from "test/token/ERC20Mock.sol";
import {Assertions} from "test/utils/Assertions.sol";

contract PremiaAirdripTest is Test, Assertions {
    IERC20 internal premia;
    PremiaAirdrip internal premiaAirdrip;

    address internal owner;
    address internal alice;
    address internal bob;
    address internal carol;

    UD60x18 internal aliceAllocation;
    UD60x18 internal bobAllocation;
    UD60x18 internal carolAllocation;

    uint256 internal totalAllocation;
    UD60x18 internal emissionRate;
    uint256[] internal vestingDates;

    IPremiaAirdrip.User[] internal users;

    function setUp() public {
        vm.createSelectFork({blockNumber: 194768525, urlOrAlias: "arbitrum_one"});

        premia = IERC20(0x51fC0f6660482Ea73330E414eFd7808811a57Fa2);

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");

        users.push(IPremiaAirdrip.User({addr: alice, influence: ud(2_000_000e18)}));
        users.push(IPremiaAirdrip.User({addr: bob, influence: ud(10_000_000e18)}));
        users.push(IPremiaAirdrip.User({addr: carol, influence: ud(8_000_000e18)}));

        owner = makeAddr("owner");

        vm.startPrank(owner);
        PremiaAirdrip implementation = new PremiaAirdrip();
        ProxyUpgradeableOwnable proxy = new ProxyUpgradeableOwnable(address(implementation));
        premiaAirdrip = PremiaAirdrip(address(proxy));

        totalAllocation = premiaAirdrip.TOTAL_ALLOCATION().unwrap();
        emissionRate = ud(2_000_000e18) / ud(20_000_000e18) / ud(12e18);

        deal(address(premia), owner, totalAllocation);
        premia.approve(address(premiaAirdrip), totalAllocation);
        vm.stopPrank();

        aliceAllocation = emissionRate * users[0].influence;
        bobAllocation = emissionRate * users[1].influence;
        carolAllocation = emissionRate * users[2].influence;

        vestingDates = [
            1723708800, // Thu Aug 15 2024 08:00:00 GMT+0000
            1726387200, // Sun Sep 15 2024 08:00:00 GMT+0000
            1728979200, // Tue Oct 15 2024 08:00:00 GMT+0000
            1731657600, // Fri Nov 15 2024 08:00:00 GMT+0000
            1734249600, // Sun Dec 15 2024 08:00:00 GMT+0000
            1736928000, // Wed Jan 15 2025 08:00:00 GMT+0000
            1739606400, // Sat Feb 15 2025 08:00:00 GMT+0000
            1742025600, // Sat Mar 15 2025 08:00:00 GMT+0000
            1744704000, // Tue Apr 15 2025 08:00:00 GMT+0000
            1747296000, // Thu May 15 2025 08:00:00 GMT+0000
            1749974400, // Sun Jun 15 2025 08:00:00 GMT+0000
            1752566400 // Tue Jul 15 2025 08:00:00 GMT+0000
        ];
    }

    event Initialized(UD60x18 emissionRate, UD60x18 totalInfluence);

    function test_initialize_Success() public {
        vm.expectEmit(false, false, false, true);
        emit Initialized(emissionRate, ud(20_000_000e18));

        vm.prank(owner);
        premiaAirdrip.initialize(users);
        assertEq(premia.balanceOf(address(premiaAirdrip)), totalAllocation);
    }

    function test_initialize_RevertIf_NotOwner() public {
        IPremiaAirdrip.User[] memory _users = new IPremiaAirdrip.User[](0);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(alice);
        premiaAirdrip.initialize(_users);
    }

    function test_initialize_RevertIf_ArrayEmpty() public {
        IPremiaAirdrip.User[] memory _users = new IPremiaAirdrip.User[](0);
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ArrayEmpty.selector);
        vm.prank(owner);
        premiaAirdrip.initialize(_users);
    }

    function test_initialize_RevertIf_InvalidUser() public {
        IPremiaAirdrip.User[] memory _users = new IPremiaAirdrip.User[](3);
        _users[0] = (IPremiaAirdrip.User({addr: alice, influence: ud(2_000_000e18)}));
        _users[1] = (IPremiaAirdrip.User({addr: address(0), influence: ud(10_000_000e18)}));
        _users[2] = (IPremiaAirdrip.User({addr: carol, influence: ud(8_000_000e18)}));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPremiaAirdrip.PremiaAirdrip__InvalidUser.selector,
                _users[1].addr,
                _users[1].influence
            )
        );

        vm.prank(owner);
        premiaAirdrip.initialize(_users);

        _users[0] = (IPremiaAirdrip.User({addr: alice, influence: ud(2_000_000e18)}));
        _users[1] = (IPremiaAirdrip.User({addr: bob, influence: ud(10_000_000e18)}));
        _users[2] = (IPremiaAirdrip.User({addr: carol, influence: ONE - ud(1)}));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPremiaAirdrip.PremiaAirdrip__InvalidUser.selector,
                _users[2].addr,
                _users[2].influence
            )
        );

        vm.prank(owner);
        premiaAirdrip.initialize(_users);
    }

    function test_initialize_RevertIf_Initialized() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__Initialized.selector);
        vm.prank(owner);
        premiaAirdrip.initialize(users);
    }

    function test_claim_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premia.balanceOf(alice), ZERO);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ZERO);

        IPremiaAirdrip.Allocation[12] memory allocations = premiaAirdrip.previewVestingSchedule(alice);

        vm.warp(allocations[0].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(1e18) * aliceAllocation);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ZERO);

        vm.warp(allocations[2].vestDate);
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(1e18) * aliceAllocation);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(3e18) * carolAllocation);

        vm.warp(allocations[4].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(5e18) * aliceAllocation);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(5e18) * carolAllocation);

        vm.warp(allocations[11].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(12e18) * aliceAllocation);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(5e18) * carolAllocation);

        vm.warp(allocations[11].vestDate + 90 days);
        vm.prank(bob);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(12e18) * aliceAllocation);
        assertEq(premia.balanceOf(bob), ud(12e18) * bobAllocation);
        assertEq(premia.balanceOf(carol), ud(12e18) * carolAllocation);

        assertApproxEqAbs(premia.balanceOf(address(premiaAirdrip)), 0, 80000000); // some dust remains in the contract
    }

    function test_claim_RevertIf_NotInitialized() public {
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__NotInitialized.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_RevertIf_ZeroAmountClaimable() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory allocations = premiaAirdrip.previewVestingSchedule(alice);
        vm.warp(allocations[11].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(12e18) * aliceAllocation);

        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_CanOnlyClaimOncePerPeriod() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory allocations = premiaAirdrip.previewVestingSchedule(alice);
        vm.warp(allocations[5].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(6e18) * aliceAllocation);

        vm.warp(allocations[5].vestDate + 15 days); // less than 1 month since last claim
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_CannotClaimBeforeVestingStart() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory allocations = premiaAirdrip.previewVestingSchedule(alice);
        vm.warp(allocations[0].vestDate - 1);

        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_previewVestingSchedule_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory aliceVestingSchedule = premiaAirdrip.previewVestingSchedule(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(aliceVestingSchedule[i].amount, aliceAllocation);
            assertEq(aliceVestingSchedule[i].vestDate, vestingDates[i]);
        }

        IPremiaAirdrip.Allocation[12] memory bobVestingSchedule = premiaAirdrip.previewVestingSchedule(bob);
        for (uint i = 0; i < 12; i++) {
            assertEq(bobVestingSchedule[i].amount, bobAllocation);
            assertEq(bobVestingSchedule[i].vestDate, vestingDates[i]);
        }

        IPremiaAirdrip.Allocation[12] memory carolVestingSchedule = premiaAirdrip.previewVestingSchedule(carol);
        for (uint i = 0; i < 12; i++) {
            assertEq(carolVestingSchedule[i].amount, carolAllocation);
            assertEq(carolVestingSchedule[i].vestDate, vestingDates[i]);
        }
    }

    function test_previewClaimedAllocations_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory aliceClaimedAllocations = premiaAirdrip.previewClaimedAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(aliceClaimedAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(aliceClaimedAllocations[0].amount, 0);
        assertEq(aliceClaimedAllocations[1].amount, 0);
        assertEq(aliceClaimedAllocations[2].amount, 0);
        assertEq(aliceClaimedAllocations[3].amount, 0);
        assertEq(aliceClaimedAllocations[4].amount, 0);
        assertEq(aliceClaimedAllocations[5].amount, 0);
        assertEq(aliceClaimedAllocations[6].amount, 0);
        assertEq(aliceClaimedAllocations[7].amount, 0);
        assertEq(aliceClaimedAllocations[8].amount, 0);
        assertEq(aliceClaimedAllocations[9].amount, 0);
        assertEq(aliceClaimedAllocations[10].amount, 0);
        assertEq(aliceClaimedAllocations[11].amount, 0);

        vm.warp(aliceClaimedAllocations[1].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();

        aliceClaimedAllocations = premiaAirdrip.previewClaimedAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(aliceClaimedAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(aliceClaimedAllocations[0].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[1].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[2].amount, 0);
        assertEq(aliceClaimedAllocations[3].amount, 0);
        assertEq(aliceClaimedAllocations[4].amount, 0);
        assertEq(aliceClaimedAllocations[5].amount, 0);
        assertEq(aliceClaimedAllocations[6].amount, 0);
        assertEq(aliceClaimedAllocations[7].amount, 0);
        assertEq(aliceClaimedAllocations[8].amount, 0);
        assertEq(aliceClaimedAllocations[9].amount, 0);
        assertEq(aliceClaimedAllocations[10].amount, 0);
        assertEq(aliceClaimedAllocations[11].amount, 0);

        vm.warp(aliceClaimedAllocations[6].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();

        aliceClaimedAllocations = premiaAirdrip.previewClaimedAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(aliceClaimedAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(aliceClaimedAllocations[0].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[1].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[2].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[3].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[4].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[5].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[6].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[7].amount, 0);
        assertEq(aliceClaimedAllocations[8].amount, 0);
        assertEq(aliceClaimedAllocations[9].amount, 0);
        assertEq(aliceClaimedAllocations[10].amount, 0);
        assertEq(aliceClaimedAllocations[11].amount, 0);

        vm.warp(aliceClaimedAllocations[11].vestDate + 90 days);
        vm.prank(alice);
        premiaAirdrip.claim();

        aliceClaimedAllocations = premiaAirdrip.previewClaimedAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(aliceClaimedAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(aliceClaimedAllocations[0].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[1].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[2].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[3].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[4].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[5].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[6].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[7].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[8].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[9].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[10].amount, aliceAllocation);
        assertEq(aliceClaimedAllocations[11].amount, aliceAllocation);
    }

    function test_previewPendingAllocations_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        IPremiaAirdrip.Allocation[12] memory alicePendingAllocations = premiaAirdrip.previewPendingAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(alicePendingAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(alicePendingAllocations[0].amount, aliceAllocation);
        assertEq(alicePendingAllocations[1].amount, aliceAllocation);
        assertEq(alicePendingAllocations[2].amount, aliceAllocation);
        assertEq(alicePendingAllocations[3].amount, aliceAllocation);
        assertEq(alicePendingAllocations[4].amount, aliceAllocation);
        assertEq(alicePendingAllocations[5].amount, aliceAllocation);
        assertEq(alicePendingAllocations[6].amount, aliceAllocation);
        assertEq(alicePendingAllocations[7].amount, aliceAllocation);
        assertEq(alicePendingAllocations[8].amount, aliceAllocation);
        assertEq(alicePendingAllocations[9].amount, aliceAllocation);
        assertEq(alicePendingAllocations[10].amount, aliceAllocation);
        assertEq(alicePendingAllocations[11].amount, aliceAllocation);

        vm.warp(alicePendingAllocations[1].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();

        alicePendingAllocations = premiaAirdrip.previewPendingAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(alicePendingAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(alicePendingAllocations[0].amount, 0);
        assertEq(alicePendingAllocations[1].amount, 0);
        assertEq(alicePendingAllocations[2].amount, aliceAllocation);
        assertEq(alicePendingAllocations[3].amount, aliceAllocation);
        assertEq(alicePendingAllocations[4].amount, aliceAllocation);
        assertEq(alicePendingAllocations[5].amount, aliceAllocation);
        assertEq(alicePendingAllocations[6].amount, aliceAllocation);
        assertEq(alicePendingAllocations[7].amount, aliceAllocation);
        assertEq(alicePendingAllocations[8].amount, aliceAllocation);
        assertEq(alicePendingAllocations[9].amount, aliceAllocation);
        assertEq(alicePendingAllocations[10].amount, aliceAllocation);
        assertEq(alicePendingAllocations[11].amount, aliceAllocation);

        vm.warp(alicePendingAllocations[6].vestDate);
        vm.prank(alice);
        premiaAirdrip.claim();

        alicePendingAllocations = premiaAirdrip.previewPendingAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(alicePendingAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(alicePendingAllocations[0].amount, 0);
        assertEq(alicePendingAllocations[1].amount, 0);
        assertEq(alicePendingAllocations[2].amount, 0);
        assertEq(alicePendingAllocations[3].amount, 0);
        assertEq(alicePendingAllocations[4].amount, 0);
        assertEq(alicePendingAllocations[5].amount, 0);
        assertEq(alicePendingAllocations[6].amount, 0);
        assertEq(alicePendingAllocations[7].amount, aliceAllocation);
        assertEq(alicePendingAllocations[8].amount, aliceAllocation);
        assertEq(alicePendingAllocations[9].amount, aliceAllocation);
        assertEq(alicePendingAllocations[10].amount, aliceAllocation);
        assertEq(alicePendingAllocations[11].amount, aliceAllocation);

        vm.warp(alicePendingAllocations[11].vestDate + 90 days);
        vm.prank(alice);
        premiaAirdrip.claim();

        alicePendingAllocations = premiaAirdrip.previewPendingAllocations(alice);
        for (uint i = 0; i < 12; i++) {
            assertEq(alicePendingAllocations[i].vestDate, vestingDates[i]);
        }

        assertEq(alicePendingAllocations[0].amount, 0);
        assertEq(alicePendingAllocations[1].amount, 0);
        assertEq(alicePendingAllocations[2].amount, 0);
        assertEq(alicePendingAllocations[3].amount, 0);
        assertEq(alicePendingAllocations[4].amount, 0);
        assertEq(alicePendingAllocations[5].amount, 0);
        assertEq(alicePendingAllocations[6].amount, 0);
        assertEq(alicePendingAllocations[7].amount, 0);
        assertEq(alicePendingAllocations[8].amount, 0);
        assertEq(alicePendingAllocations[9].amount, 0);
        assertEq(alicePendingAllocations[10].amount, 0);
        assertEq(alicePendingAllocations[11].amount, 0);
    }
}
