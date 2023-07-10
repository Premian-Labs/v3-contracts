// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

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
        UD60x18 rewardsPerYear = ud(1e18);
        DualMining implementation = new DualMining(address(vaultMining));
        DualMiningProxy proxy = new DualMiningProxy(address(implementation), address(rewardToken), rewardsPerYear);

        dualMining = DualMining(address(proxy));
    }

    function _addRewards() internal {
        vm.startPrank(alice);
        rewardToken.mint(alice, 1000e18);
        rewardToken.approve(address(dualMining), 1000e18);
        dualMining.addRewards(ud(1000e18));
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

        assertEq(dualMining.getRewardsAvailable(), 1000e18);
    }

    function test_addRewards_RevertIf_MiningEnded() public {
        // ToDo
    }

    function test_updatePool_Success() public {
        // ToDo
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

    function test_updateUser_Success() public {
        // ToDo
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

    function test_claim_Success() public {
        // ToDo
    }

    function test_claim_RevertIf_NotInitialized() public {
        vm.expectRevert(IDualMining.DualMining__NotInitialized.selector);
        vm.prank(alice);
        dualMining.claim();
    }
}
