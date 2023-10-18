// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import "forge-std/console2.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {Test} from "forge-std/Test.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {IVaultMining} from "contracts/mining/vaultMining/IVaultMining.sol";
import {VaultMining} from "contracts/mining/vaultMining/VaultMining.sol";
import {VaultMiningProxy} from "contracts/mining/vaultMining/VaultMiningProxy.sol";
import {IVxPremia} from "contracts/staking/IVxPremia.sol";
import {VxPremia} from "contracts/staking/VxPremia.sol";
import {VxPremiaProxy} from "contracts/staking/VxPremiaProxy.sol";
import {VxPremiaStorage} from "contracts/staking/VxPremiaStorage.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";
import {IVaultRegistry} from "contracts/vault/IVaultRegistry.sol";
import {VaultMock} from "contracts/test/vault/VaultMock.sol";
import {VaultRegistry} from "contracts/vault/VaultRegistry.sol";
import {OptionRewardMock} from "../../../contracts/test/mining/optionReward/OptionRewardMock.sol";

import {Assertions} from "../../Assertions.sol";
import {DebugUtils} from "../../DebugUtils.sol";

contract ProxyManagerMock {
    function getPoolList() external pure returns (address[] memory poolList) {
        return poolList;
    }
}

contract VaultMiningTest is Test, Assertions {
    uint256 internal constant ONE_DAY = 24 * 3600;

    address internal admin;
    address internal alice;
    address internal bob;
    address internal carol;

    VaultRegistry internal vaultRegistry;
    VaultMining internal vaultMining;
    ERC20Mock internal premia;
    VxPremia internal vxPremia;
    OptionRewardMock internal optionReward;

    VaultMock internal vaultA;
    VaultMock internal vaultB;
    VaultMock internal vaultC;
    VaultMock internal vaultD;
    VaultMock internal vaultNotRegistered;

    function setUp() public {
        admin = vm.addr(1);
        alice = vm.addr(2);
        bob = vm.addr(3);
        carol = vm.addr(4);

        address vaultRegistryImpl = address(new VaultRegistry());
        address vaultRegistryProxy = address(new ProxyUpgradeableOwnable(vaultRegistryImpl));
        vaultRegistry = VaultRegistry(vaultRegistryProxy);

        premia = new ERC20Mock("PREMIA", 18);
        address usdc = address(new ERC20Mock("USDC", 6));

        address proxyManager = address(new ProxyManagerMock());

        address vxPremiaImpl = address(
            new VxPremia(proxyManager, address(0), address(premia), usdc, address(0), vaultRegistryProxy)
        );
        address vxPremiaProxy = address(new VxPremiaProxy(address(vxPremiaImpl)));
        vxPremia = VxPremia(address(vxPremiaProxy));

        optionReward = new OptionRewardMock(address(premia));

        address vaultMiningImpl = address(
            new VaultMining(address(vaultRegistry), address(premia), address(vxPremia), address(optionReward))
        );
        address vaultMiningProxy = address(new VaultMiningProxy(address(vaultMiningImpl), ud(365 * 1000e18)));
        vaultMining = VaultMining(vaultMiningProxy);

        vm.startPrank(admin);

        premia.mint(admin, 500_000e18);
        premia.approve(address(vaultMining), 500_000e18);
        vaultMining.addRewards(ud(200_000e18));
        premia.approve(address(vxPremia), 500_000e18);
        vxPremia.stake(100_000e18, uint64(ONE_DAY * 365 * 4));

        vm.stopPrank();

        vaultA = new VaultMock(address(vaultMining));
        vaultB = new VaultMock(address(vaultMining));
        vaultC = new VaultMock(address(vaultMining));
        vaultD = new VaultMock(address(vaultMining));
        vaultNotRegistered = new VaultMock(address(vaultMining));

        vaultRegistry.addVault(
            address(vaultA),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        vaultRegistry.addVault(
            address(vaultB),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        vaultRegistry.addVault(
            address(vaultC),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );
        vaultRegistry.addVault(
            address(vaultD),
            address(0),
            keccak256("VAULT"),
            IVaultRegistry.TradeSide.Sell,
            IVaultRegistry.OptionType.Call
        );

        vm.prank(admin);
        VxPremiaStorage.Vote[] memory votes = new VxPremiaStorage.Vote[](4);
        votes[0] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultA))
        });
        votes[1] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultB))
        });
        votes[2] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultC))
        });
        votes[3] = VxPremiaStorage.Vote({
            amount: 1e18,
            version: IVxPremia.VoteVersion.VaultV3,
            target: abi.encodePacked(address(vaultD))
        });
        vxPremia.castVotes(votes);

        vaultMining.updateVault(address(vaultA));
        vaultMining.updateVault(address(vaultB));
        vaultMining.updateVault(address(vaultC));
        vaultMining.updateVault(address(vaultD));
    }

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
        vaultMining.updateUser(address(alice), ud(1000e18), ud(1000e18), ud(1e18));
    }

    function test_vaultMining_DistributeRewardsCorrectly() public {
        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        // Precision used in assertions
        uint256 delta = 1e6;

        uint256 ts = block.timestamp;

        vaultB.mint(alice, 10e18);

        vm.warp(ts + ONE_DAY);
        vaultA.mint(alice, 10e18);

        vm.warp(ts + 3 * ONE_DAY);
        vaultA.mint(bob, 20e18);

        // There is 4 vaults with equal alloc points, with premia reward of 1k per day
        // Each pool should get 250 reward per day. Lp1 should therefore have 2 * 250 pending reward now for vaultA
        assertApproxEqAbs(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)).unwrap(), 500e18, delta);

        vm.warp(ts + 6 * ONE_DAY);
        vaultA.mint(carol, 30e18);

        vm.warp(ts + 8 * ONE_DAY);
        vaultA.mint(alice, 10e18);

        // Alice should have pending reward of : 2*250 + 3*1/3*250 + 2*1/6*250 = 833.3333333333333
        assertApproxEqAbs(
            (vaultMining.getUserRewards(alice) + vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)))
                .unwrap(),
            833.3333333333333e18,
            delta
        );

        // Bob should have pending reward of: 3*2/3*250 + 2*2/6*250 + 5*2/7*250 = 1023.8095238095239
        vm.warp(ts + 13 * ONE_DAY);
        vaultA.burn(bob, 5e18);

        assertApproxEqAbs(
            (vaultMining.getUserRewards(bob) + vaultMining.getPendingUserRewardsFromVault(bob, address(vaultA)))
                .unwrap(),
            1023.8095238095239e18,
            delta
        );

        vm.warp(ts + 14 * ONE_DAY);
        vaultA.burn(alice, 20e18);

        vm.warp(ts + 15 * ONE_DAY);
        vaultA.burn(bob, 15e18);

        vm.warp(ts + 16 * ONE_DAY);
        vaultA.burn(carol, 30e18);

        // 1k per day emission, during 16 days
        // We also need to add 250 to that amount, as vaultA had 0 shares during first day of emission, leading to emission being added back to available rewards
        assertApproxEqAbs(vaultMining.getRewardsAvailable().unwrap(), 200_000e18 - 16_000e18 + 250e18, delta, "aa");

        vaultMining.updateVaults();

        // After update of all vaults is triggered, rewards of 2 vaults (8k) are added back to available rewards, as those 2 vaults have 0 totalShares
        assertApproxEqAbs(vaultMining.getRewardsAvailable().unwrap(), 200_000e18 - 16_000e18 / 2 + 250e18, delta, "ab");

        // Alice should have: 833.3333333333333 + 5*2/7*250 + 1*2/6.5*250 = 1267.3992673992673
        assertApproxEqAbs(
            (vaultMining.getUserRewards(alice) + vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)))
                .unwrap(),
            1267.3992673992673e18,
            delta
        );

        // Bob should have: 1023.8095238095239 + 1*1.5/6.5 * 250 + 1*1.5/4.5*250 = 1164.8351648351647
        assertApproxEqAbs(
            (vaultMining.getUserRewards(bob) + vaultMining.getPendingUserRewardsFromVault(bob, address(vaultA)))
                .unwrap(),
            1164.8351648351647e18,
            delta
        );

        // Carol should have: 2*3/6*250 + 5*3/7*250 + 1*3/6.5*250 + 1*3/4.5*250 + 1*250 = 1317.7655677655678
        assertApproxEqAbs(
            (vaultMining.getUserRewards(carol) + vaultMining.getPendingUserRewardsFromVault(carol, address(vaultA)))
                .unwrap(),
            1317.7655677655678e18,
            delta
        );

        assertApproxEqAbs(
            (vaultMining.getPendingUserRewardsFromVault(alice, address(vaultB))).unwrap(),
            4000e18,
            delta
        );

        vm.prank(alice);
        vaultMining.claimAll(vaultList);

        vm.prank(bob);
        vaultMining.claimAll(vaultList);

        vm.prank(carol);
        vaultMining.claimAll(vaultList);

        assertApproxEqAbs(optionReward.balanceOf(alice, 0), 1267.3992673992673e18, delta);
        assertApproxEqAbs(optionReward.balanceOf(bob, 0), 1164.8351648351647e18, delta);
        assertApproxEqAbs(optionReward.balanceOf(carol, 0), 1317.7655677655678e18, delta);
    }

    function test_vaultMining_StopDistributingRewards_IfRewardsRunOut() public {
        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vaultB.mint(alice, 10e18);
        vaultC.mint(alice, 10e18);
        vaultD.mint(alice, 10e18);

        vm.warp(ts + 4 * 200 * ONE_DAY + ONE_DAY);
        assertEq(vaultMining.getTotalUserRewards(alice), 200_000e18);

        vm.prank(alice);
        vaultMining.claimAll(vaultList);
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)), 0, "A");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultB)), 50_000e18, "B");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultC)), 50_000e18, "C");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultD)), 50_000e18, "D");
        assertEq(optionReward.balanceOf(alice, 0), 50_000e18);

        vm.warp(block.timestamp + ONE_DAY);
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)), 0, "A2");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultB)), 50_000e18, "B2");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultC)), 50_000e18, "C2");
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultD)), 50_000e18, "D2");

        vaultMining.updateVault(address(vaultA));
        vm.prank(admin);
        vaultMining.addRewards(ud(200_000e18));

        vm.warp(block.timestamp + ONE_DAY);
        assertApproxEqAbs(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)).unwrap(), 250e18, 1e6);
        assertApproxEqAbs(
            vaultMining.getPendingUserRewardsFromVault(alice, address(vaultB)).unwrap(),
            50_000e18 + 250e18,
            1e6
        );
        assertApproxEqAbs(
            vaultMining.getPendingUserRewardsFromVault(alice, address(vaultC)).unwrap(),
            50_000e18 + 250e18,
            1e6
        );
        assertApproxEqAbs(
            vaultMining.getPendingUserRewardsFromVault(alice, address(vaultD)).unwrap(),
            50_000e18 + 250e18,
            1e6
        );
    }

    function test_setRewardsPerYear_UpdateRewardsPerYear() public {
        vaultMining.setRewardsPerYear(ud(1000e18));
        assertEq(vaultMining.getRewardsPerYear(), 1000e18);
    }

    function test_setRewardsPerYear_RevertIf_NotOwner() public {
        vm.prank(alice);
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vaultMining.setRewardsPerYear(ud(1000e18));
    }

    function test_claim_Success() public {
        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vm.warp(ts + 4 * 200 * ONE_DAY + ONE_DAY);

        // Available rewards is 200k, and there is 4 vaults with equal votes, so up to 50k can be allocated to vaultA
        // Other rewards would be reallocated to LM after an update is triggered, as the 3 other vaults are empty
        assertEq(vaultMining.getTotalUserRewards(alice), 50_000e18);

        vm.prank(alice);
        vaultMining.claim(vaultList, ud(50_000e18));
        assertEq(vaultMining.getTotalUserRewards(alice), 0);
        assertEq(optionReward.balanceOf(alice, 0), 50_000e18);
    }

    function test_claim_RevertIf_NotEnoughRewards() public {
        address[] memory vaultList = new address[](1);
        vaultList[0] = address(vaultA);

        uint256 ts = block.timestamp;

        vaultA.mint(alice, 10e18);
        vm.warp(ts + 4 * 200 * ONE_DAY + ONE_DAY);

        // Available rewards is 200k, and there is 4 vaults with equal votes, so up to 50k can be allocated to vaultA
        // Other rewards would be reallocated to LM after an update is triggered, as the 3 other vaults are empty
        assertEq(vaultMining.getPendingUserRewardsFromVault(alice, address(vaultA)), 50_000e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultMining.VaultMining__InsufficientRewards.selector, alice, 50_000e18, 50_001e18)
        );
        vaultMining.claim(vaultList, ud(50_001e18));
    }
}
