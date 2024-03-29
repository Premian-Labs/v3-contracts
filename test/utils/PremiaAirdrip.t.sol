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

    UD60x18 internal aliceTokensPerSecond;
    UD60x18 internal bobTokensPerSecond;
    UD60x18 internal carolTokensPerSecond;

    uint256 internal totalAllocation;
    UD60x18 internal emissionRate;
    uint256 internal vestingStart;

    UD60x18 internal ONE_YEAR = UD60x18.wrap(365 days * 1e18);

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
        emissionRate = ud(2_000_000e18) / ud(20_000_000e18) / ud(365 days * 1e18);

        deal(address(premia), owner, totalAllocation);
        premia.approve(address(premiaAirdrip), totalAllocation);
        vm.stopPrank();

        aliceTokensPerSecond = emissionRate * users[0].influence;
        bobTokensPerSecond = emissionRate * users[1].influence;
        carolTokensPerSecond = emissionRate * users[2].influence;
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

    function test_claim_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premia.balanceOf(alice), ZERO);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ZERO);

        vm.warp(vestingStart + 1 seconds);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), aliceTokensPerSecond);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ZERO);

        vm.warp(vestingStart + 100 seconds);
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), aliceTokensPerSecond);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(100e18) * carolTokensPerSecond);

        vm.warp(vestingStart + 100 days);
        vm.prank(alice);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(100 days * 1e18) * aliceTokensPerSecond);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(100 days * 1e18) * carolTokensPerSecond);

        vm.warp(vestingStart + 302 days);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(302 days * 1e18) * aliceTokensPerSecond);
        assertEq(premia.balanceOf(bob), ZERO);
        assertEq(premia.balanceOf(carol), ud(100 days * 1e18) * carolTokensPerSecond);

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        vm.prank(alice);
        premiaAirdrip.claim();
        vm.prank(bob);
        premiaAirdrip.claim();
        vm.prank(carol);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ONE_YEAR * aliceTokensPerSecond);
        assertEq(premia.balanceOf(bob), ONE_YEAR * bobTokensPerSecond);
        assertEq(premia.balanceOf(carol), ONE_YEAR * carolTokensPerSecond);
    }

    function test_claim_RevertIf_NotClaimable() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        vm.warp(vestingStart + 10 seconds);
        vm.prank(alice);
        premiaAirdrip.claim();
        assertEq(premia.balanceOf(alice), ud(10e18) * aliceTokensPerSecond);

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
        assertEq(premia.balanceOf(alice), ONE_YEAR * aliceTokensPerSecond);

        vm.warp(vestingStart + 365 days + 1 seconds); // 365 days and one second after vesting start
        vm.expectRevert(IPremiaAirdrip.PremiaAirdrip__ZeroAmountClaimable.selector);
        vm.prank(alice);
        premiaAirdrip.claim();
    }

    function test_previewMaxClaimableAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        UD60x18 aliceMaxClaimable = ONE_YEAR * aliceTokensPerSecond;
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 100 days);
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 302 days);
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertEq(premiaAirdrip.previewMaxClaimableAmount(alice), aliceMaxClaimable);
    }

    function test_previewClaimableAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premiaAirdrip.previewClaimableAmount(alice), ZERO);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewClaimableAmount(alice), aliceTokensPerSecond);

        vm.prank(alice);
        premiaAirdrip.claim();
        UD60x18 totalClaimed = aliceTokensPerSecond;

        vm.warp(vestingStart + 100 seconds);
        UD60x18 expectedClaim = ud(100e18) * aliceTokensPerSecond - totalClaimed;
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 100 days);
        expectedClaim = ud(100 days * 1e18) * aliceTokensPerSecond - totalClaimed;
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 302 days);
        expectedClaim = ud(302 days * 1e18) * aliceTokensPerSecond - totalClaimed;
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = totalClaimed + expectedClaim;

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        expectedClaim = ONE_YEAR * aliceTokensPerSecond - totalClaimed;
        assertEq(premiaAirdrip.previewClaimableAmount(alice), expectedClaim);
    }

    function test_previewClaimableRemaining_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        UD60x18 aliceMaxClaimable = ONE_YEAR * aliceTokensPerSecond;
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable);

        vm.prank(alice);
        premiaAirdrip.claim();
        UD60x18 totalClaimed = aliceTokensPerSecond;

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable - totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(100e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 100 days);
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable - totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(100 days * 1e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 302 days);
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable - totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(302 days * 1e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertEq(premiaAirdrip.previewClaimableRemaining(alice), aliceMaxClaimable - totalClaimed);
    }

    function test_previewClaimedAmount_Success() public {
        vm.prank(owner);
        premiaAirdrip.initialize(users);

        assertEq(premiaAirdrip.previewClaimedAmount(alice), ZERO);

        vm.warp(vestingStart + 1 seconds);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), ZERO);

        vm.prank(alice);
        premiaAirdrip.claim();
        UD60x18 totalClaimed = aliceTokensPerSecond;

        vm.warp(vestingStart + 100 seconds);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(100e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 100 days);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(100 days * 1e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 302 days);
        assertEq(premiaAirdrip.previewClaimedAmount(alice), totalClaimed);

        vm.prank(alice);
        premiaAirdrip.claim();
        totalClaimed = ud(302 days * 1e18) * aliceTokensPerSecond;

        vm.warp(vestingStart + 375 days); // 10 days after vesting end
        assertEq(premiaAirdrip.previewClaimedAmount(alice), totalClaimed);
    }
}
