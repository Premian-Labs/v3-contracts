// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {PRBMathExtra} from "contracts/libraries/PRBMathExtra.sol";
import {UD50x28, ud50x28} from "contracts/libraries/UD50x28.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {IPremiaAirdrip} from "contracts/utils/IPremiaAirdrip.sol";
import {PremiaAirdrip} from "contracts/utils/PremiaAirdrip.sol";

import {ERC20Mock} from "test/token/ERC20Mock.sol";
import {Assertions} from "test/utils/Assertions.sol";

contract PremiaAirdripTest is Test, Assertions {
    using PRBMathExtra for UD60x18;

    IERC20 internal premia;
    PremiaAirdrip internal premiaAirdrip;

    address internal owner;
    address internal alice;
    address internal bob;
    address internal carol;

    UD50x28 internal aliceMaxClaimableAmount;
    UD50x28 internal bobMaxClaimableAmount;
    UD50x28 internal carolMaxClaimableAmount;

    uint256 internal totalAllocation;
    UD60x18 internal premiaPerInfluence;
    uint256 internal vestingStart;
    uint256 internal vestingDuration;

    uint256 internal constant delta = 10;

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
        vestingStart = premiaAirdrip.VESTING_START();
        vestingDuration = premiaAirdrip.VESTING_DURATION();

        premiaPerInfluence = ud(2_000_000e18) / ud(20_000_000e18);

        deal(address(premia), owner, totalAllocation);
        premia.approve(address(premiaAirdrip), totalAllocation);
        vm.stopPrank();

        aliceMaxClaimableAmount = (users[0].influence * premiaPerInfluence).intoUD50x28();
        bobMaxClaimableAmount = (users[1].influence * premiaPerInfluence).intoUD50x28();
        carolMaxClaimableAmount = (users[2].influence * premiaPerInfluence).intoUD50x28();
    }

    event Initialized(UD60x18 premiaPerInfluence, UD60x18 totalInfluence);

    function test_initialize_Success() public {
        assertEq(premiaAirdrip.VESTING_DURATION(), 365 days);
        assertEq(premiaAirdrip.VESTING_START(), 1723708800);

        vm.expectEmit(false, false, false, true);
        emit Initialized(premiaPerInfluence, ud(20_000_000e18));
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

    function test_initialize_RevertIf_Initialized() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__Initialized.selector);
        vm.prank(owner);
        premiaAirdrip.initialize(users);
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
        _users[2] = (IPremiaAirdrip.User({addr: carol, influence: ud(1e18) - ud(1)}));

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

    function test_initialize_RevertIf_UserAlreadyExists() public {
        IPremiaAirdrip.User[] memory _users = new IPremiaAirdrip.User[](3);
        _users[0] = (IPremiaAirdrip.User({addr: alice, influence: ud(2_000_000e18)}));
        _users[1] = (IPremiaAirdrip.User({addr: alice, influence: ud(10_000_000e18)}));
        _users[2] = (IPremiaAirdrip.User({addr: carol, influence: ud(8_000_000e18)}));

        vm.expectRevert(
            abi.encodeWithSelector(IPremiaAirdrip.PremiaAirdrip__UserAlreadyExists.selector, _users[1].addr)
        );

        vm.prank(owner);
        premiaAirdrip.initialize(_users);
    }

    function calculateClaimablePercent(uint256 duration) internal view returns (UD50x28) {
        return ud50x28(duration * 1e28) / ud50x28(vestingDuration * 1e28);
    }

    function calculatedClaimableAmount(uint256 duration, UD50x28 maxClaimableAmount) internal view returns (uint256) {
        return (calculateClaimablePercent(duration) * maxClaimableAmount).intoUD60x18().unwrap();
    }

    function test_claim_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premia.balanceOf(alice), 0);
        assertEq(premia.balanceOf(bob), 0);
        assertEq(premia.balanceOf(carol), 0);

        vm.warp(vestingStart + 1 seconds);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), calculatedClaimableAmount(1 seconds, aliceMaxClaimableAmount));
        assertEq(premia.balanceOf(bob), 0);
        assertEq(premia.balanceOf(carol), 0);

        vm.warp(vestingStart + 100 seconds);
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), calculatedClaimableAmount(1 seconds, aliceMaxClaimableAmount));
        assertEq(premia.balanceOf(bob), 0);
        assertEq(premia.balanceOf(carol), calculatedClaimableAmount(100 seconds, carolMaxClaimableAmount));

        vm.warp(vestingStart + 100 days);
        vm.prank(alice);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();
        // NOTE, there is a small rounding error here since the actual balance is based on multiple claims whereas the
        // comparator is taking calculating the amount assuming a single claim is being made.
        assertApproxEqAbs(premia.balanceOf(alice), calculatedClaimableAmount(100 days, aliceMaxClaimableAmount), delta);
        assertEq(premia.balanceOf(bob), 0);
        assertApproxEqAbs(premia.balanceOf(carol), calculatedClaimableAmount(100 days, carolMaxClaimableAmount), delta);

        vm.warp(vestingStart + 302 days);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertApproxEqAbs(premia.balanceOf(alice), calculatedClaimableAmount(302 days, aliceMaxClaimableAmount), delta);
        assertEq(premia.balanceOf(bob), 0);
        assertApproxEqAbs(premia.balanceOf(carol), calculatedClaimableAmount(100 days, carolMaxClaimableAmount), delta);

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        vm.prank(alice);
        premiaAirdrip.claim();
        vm.prank(bob);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();

        assertApproxEqAbs(premia.balanceOf(alice), aliceMaxClaimableAmount.intoUD60x18().unwrap(), delta);
        assertEq(premia.balanceOf(bob), bobMaxClaimableAmount.intoUD60x18().unwrap());
        assertApproxEqAbs(premia.balanceOf(carol), carolMaxClaimableAmount.intoUD60x18().unwrap(), delta);
    }

    function test_claim_RevertIf_NotClaimable() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        vm.warp(vestingStart + 10 seconds);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), calculatedClaimableAmount(10 seconds, aliceMaxClaimableAmount));

        vm.expectRevert(
            abi.encodeWithSelector(
                IPremiaAirdrip.PremiaAirdrip__NotClaimable.selector,
                vestingStart + 10 seconds,
                block.timestamp
            )
        );

        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_RevertIf_NotVested() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        vm.expectRevert(
            abi.encodeWithSelector(IPremiaAirdrip.PremiaAirdrip__NotVested.selector, vestingStart, block.timestamp)
        );

        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_RevertIf_NotInitialized() public {
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__NotInitialized.selector);
        vm.warp(vestingStart);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_claim_RevertIf_ZeroAmountClaimable() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        vm.warp(vestingStart);
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 365 days); // 365 days after vesting start
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), aliceMaxClaimableAmount.intoUD60x18().unwrap());

        vm.warp(vestingStart + 365 days + 1 seconds); // 365 days and one second after vesting start
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_previewTotalAllocationAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        uint256 aliceMaxClaimable = aliceMaxClaimableAmount.intoUD60x18().unwrap();
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 100 days);
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 302 days);
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premiaAirdrip.previewTotalAllocationAmount(alice), aliceMaxClaimable);
    }

    function test_previewClaimableAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premiaAirdrip.previewClaimableAmount(alice), 0);

        vm.warp(vestingStart + 1 seconds);
        uint256 expectedClaim = calculatedClaimableAmount(1 seconds, aliceMaxClaimableAmount);
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);

        vm.prank(alice);
        premiaAirdrip.claim();
        uint256 totalClaimed = expectedClaim;

        vm.warp(vestingStart + 100 seconds);
        expectedClaim = calculatedClaimableAmount(100 seconds, aliceMaxClaimableAmount) - totalClaimed;
        assertApproxEqAbs(premiaAirdrip.previewClaimableAmount(alice), expectedClaim, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 100 days);
        expectedClaim = calculatedClaimableAmount(100 days, aliceMaxClaimableAmount) - totalClaimed;
        assertApproxEqAbs(premiaAirdrip.previewClaimableAmount(alice), expectedClaim, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 302 days);
        expectedClaim = calculatedClaimableAmount(302 days, aliceMaxClaimableAmount) - totalClaimed;
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        expectedClaim = aliceMaxClaimableAmount.intoUD60x18().unwrap() - totalClaimed;
        assertApproxEqAbs(premiaAirdrip.previewClaimableAmount(alice), expectedClaim, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premiaAirdrip.previewClaimableAmount(alice), 0);
    }

    function test_previewClaimRemaining_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        uint256 aliceMaxClaimable = aliceMaxClaimableAmount.intoUD60x18().unwrap();
        assertEq(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();
        uint256 totalClaimed = calculatedClaimableAmount(1 seconds, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable - totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(100 seconds, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 100 days);
        assertApproxEqAbs(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable - totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(100 days, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 302 days);
        assertApproxEqAbs(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable - totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(302 days, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertApproxEqAbs(premiaAirdrip.previewClaimRemaining(alice), aliceMaxClaimable - totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        assertApproxEqAbs(premiaAirdrip.previewClaimRemaining(alice), 0, delta);
    }

    function test_previewClaimedAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premiaAirdrip.previewClaimedAmount(alice), 0);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), 0);

        vm.prank(alice);
        premiaAirdrip.claim();
        uint256 totalClaimed = calculatedClaimableAmount(1 seconds, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(100 seconds, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 100 days);
        assertApproxEqAbs(premiaAirdrip.previewClaimedAmount(alice), totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(100 days, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 302 days);
        assertApproxEqAbs(premiaAirdrip.previewClaimedAmount(alice), totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(302 days, aliceMaxClaimableAmount);

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertApproxEqAbs(premiaAirdrip.previewClaimedAmount(alice), totalClaimed, delta);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = calculatedClaimableAmount(365 days, aliceMaxClaimableAmount);
        assertApproxEqAbs(premiaAirdrip.previewClaimedAmount(alice), totalClaimed, delta);
    }
}
