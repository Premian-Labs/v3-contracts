// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/IReentrancyGuard.sol";

import {ProxyUpgradeableOwnableNonReentrantMock} from "contracts/test/proxy/ProxyUpgradeableOwnableNonReentrantMock.sol";

import {Assertions} from "../Assertions.sol";

contract Target {
    uint public x;

    function nonReentrantCall() external returns (uint) {
        return ++x;
    }

    function reentrantCall() external returns (uint) {
        if (x >= 5) return x;
        x++;
        this.reentrantCall();
        return x;
    }

    function callToNonReentrantCall() external returns (uint) {
        return this.nonReentrantCall();
    }

    function nonReentrantStaticcall() external view returns (uint) {
        return x;
    }

    function staticcallToNonReentrantStaticcall() external view returns (uint) {
        return this.nonReentrantStaticcall();
    }

    function callToNonReentrantStaticcall() external returns (uint) {
        uint y = 10;
        this.nonReentrantStaticcall();
        x = y;
        return x;
    }

    function callToCrossContractCall(OtherTarget otherTarget) external returns (uint) {
        x = 9;
        return otherTarget.crossContractCall(this);
    }
}

contract OtherTarget {
    function crossContractCall(Target target) external returns (uint) {
        return target.nonReentrantCall();
    }
}

contract ProxyUpgradeableOwnableNonReentrantTest is Test, Assertions {
    Target target;
    OtherTarget otherTarget;
    ProxyUpgradeableOwnableNonReentrantMock proxy;

    address owner;

    function setUp() public {
        owner = vm.addr(1);
        vm.startPrank(owner);
        proxy = new ProxyUpgradeableOwnableNonReentrantMock(address(new Target()));
        target = Target(address(proxy));
        otherTarget = new OtherTarget();
        vm.stopPrank();
    }

    function test_nonReentrant_Success() public {
        assertEq(target.x(), 0);
        assertEq(target.nonReentrantCall(), 1);
    }

    function test_nonReentrant_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.nonReentrantCall();
    }

    function test_nonReentrant_ForceUnlock_Success() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        assertEq(target.x(), 0);
        assertEq(target.nonReentrantCall(), 1);
    }

    function test_nonReentrant_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.x(), 0);
        assertEq(target.nonReentrantCall(), 1);
    }

    function test_nonReentrant_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantCall.selector);
        assertEq(target.x(), 0);
        assertEq(target.nonReentrantCall(), 1);
    }

    function test_reentrantCall_Revert() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.reentrantCall();
    }

    function test_reentrantCall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.reentrantCall();
    }

    function test_reentrantCall_ForceUnlock_Revert() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.reentrantCall();
    }

    function test_reentrantCall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.x(), 0);
        assertEq(target.reentrantCall(), 5);
    }

    function test_reentrantCall_IgnoreReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.reentrantCall.selector);
        assertEq(target.x(), 0);
        assertEq(target.reentrantCall(), 5);
    }

    function test_reentrantCall_ReentrantCallSelectorIgnored_ForceLock_Success() public {
        test_addReentrancyGuardSelectorsIgnored_ReentrantCallSelectorIgnored_ForceLock_Success();
        // assertEq(target.x(), 0); // state of `x` cannot be checked when lock is enabled
        assertEq(target.reentrantCall(), 5);
        proxy.__unlockReentrancyGuard();
    }

    function test_callToNonReentrantCall_Revert() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantCall();
    }

    function test_callToNonReentrantCall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantCall();
    }

    function test_callToNonReentrantCall_ForceUnlock_Revert() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantCall();
    }

    function test_callToNonReentrantCall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.x(), 0);
        assertEq(target.callToNonReentrantCall(), 1);
    }

    function test_callToNonReentrantCall_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantCall.selector);
        assertEq(target.x(), 0);
        assertEq(target.callToNonReentrantCall(), 1);
    }

    function test_nonReentrantStaticcall_Success() public {
        assertEq(target.nonReentrantStaticcall(), 0);
    }

    function test_nonReentrantStaticcall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.nonReentrantStaticcall();
    }

    function test_nonReentrantStaticcall_ForceUnlock_Success() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        assertEq(target.nonReentrantStaticcall(), 0);
    }

    function test_nonReentrantStaticcall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.nonReentrantStaticcall(), 0);
    }

    function test_nonReentrantStaticcall_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantStaticcall.selector);
        assertEq(target.nonReentrantStaticcall(), 0);
    }

    function test_staticcallToNonReentrantStaticcall_Success() public {
        assertEq(target.staticcallToNonReentrantStaticcall(), 0);
    }

    function test_staticcallToNonReentrantStaticcall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.staticcallToNonReentrantStaticcall();
    }

    function test_staticcallToNonReentrantStaticcall_ForceUnlock_Success() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        target.staticcallToNonReentrantStaticcall();
        assertEq(target.staticcallToNonReentrantStaticcall(), 0);
    }

    function test_staticcallToNonReentrantStaticcall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.staticcallToNonReentrantStaticcall(), 0);
    }

    function test_staticcallToNonReentrantStaticcall_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantStaticcall.selector);
        assertEq(target.staticcallToNonReentrantStaticcall(), 0);
    }

    function test_callToNonReentrantStaticcall_Revert() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantStaticcall();
    }

    function test_callToNonReentrantStaticcall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantStaticcall();
    }

    function test_callToNonReentrantStaticcall_ForceUnlock_Revert() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToNonReentrantStaticcall();
    }

    function test_callToNonReentrantStaticcall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.x(), 0);
        assertEq(target.callToNonReentrantStaticcall(), 10);
    }

    function test_callToNonReentrantStaticcall_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantStaticcall.selector);
        assertEq(target.x(), 0);
        assertEq(target.callToNonReentrantStaticcall(), 10);
    }

    function test_callToCrossContractCall_Revert() public {
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToCrossContractCall(otherTarget);
    }

    function test_callToCrossContractCall_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToCrossContractCall(otherTarget);
    }

    function test_callToCrossContractCall_ForceUnlock_Revert() public {
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.callToCrossContractCall(otherTarget);
    }

    function test_callToCrossContractCall_ReentrancyGuardDisabled_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        assertEq(target.x(), 0);
        assertEq(target.callToCrossContractCall(otherTarget), 10);
    }

    function test_callToCrossContractCall_IgnoredNonReentrantCallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantCall.selector);
        assertEq(target.x(), 0);
        assertEq(target.callToCrossContractCall(otherTarget), 10);
    }

    function test_callToNonReentrantStaticcall_IgnoreNonReentrantStaticcallSelector_Success() public {
        test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(target.nonReentrantStaticcall.selector);
        assertEq(target.callToNonReentrantStaticcall(), 10);
    }

    function test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success() public {
        vm.prank(owner);
        proxy.setReentrancyGuardDisabled(true);
        assertTrue(proxy.isReentrancyGuardDisabled());
    }

    function test_setReentrancyGuardDisabled_ReentrancyGuardEnabled_Success() public {
        vm.prank(owner);
        proxy.setReentrancyGuardDisabled(true);
        assertTrue(proxy.isReentrancyGuardDisabled());
        vm.prank(owner);
        proxy.setReentrancyGuardDisabled(false);
        assertFalse(proxy.isReentrancyGuardDisabled());
    }

    function test_setReentrancyGuardDisabled_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        proxy.setReentrancyGuardDisabled(true);
    }

    function test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_ForceLock_Success() public {
        test_setReentrancyGuardDisabled_ReentrancyGuardDisabled_Success();
        vm.prank(owner);
        proxy.__lockReentrancyGuard(); // setting lock should fail
        assertFalse(proxy.isReentrancyGuardLocked());
    }

    function test_addReentrancyGuardSelectorsIgnored_SelectorIgnored_Success(bytes4 selector) public {
        bytes4[] memory selectorsIgnored = new bytes4[](1);

        if (selector == bytes4(0)) {
            selectorsIgnored[0] = target.reentrantCall.selector;
        } else {
            selectorsIgnored[0] = selector;
        }

        vm.prank(owner);
        proxy.addReentrancyGuardSelectorsIgnored(selectorsIgnored);
        bytes4[] memory _selectorsIgnored = proxy.getReentrancyGuardSelectorsIgnored();
        assertEq(_selectorsIgnored.length, 1);
        assertEq(selectorsIgnored[0], _selectorsIgnored[0]);
    }

    function test_addReentrancyGuardSelectorsIgnored_ReentrantCallSelectorIgnored_ForceLock_Success() public {
        bytes4[] memory selectorsIgnored = new bytes4[](1);
        selectorsIgnored[0] = target.reentrantCall.selector;
        vm.startPrank(owner);
        proxy.addReentrancyGuardSelectorsIgnored(selectorsIgnored);
        proxy.__lockReentrancyGuard();
        vm.stopPrank();
        assertTrue(proxy.isReentrancyGuardLocked());
        bytes4[] memory _selectorsIgnored = proxy.getReentrancyGuardSelectorsIgnored();
        assertEq(_selectorsIgnored.length, 1);
        assertEq(selectorsIgnored[0], _selectorsIgnored[0]);
    }

    function test_addReentrancyGuardSelectorsIgnored_RevertIf_Not_Owner() public {
        bytes4[] memory selectorsIgnored = new bytes4[](1);
        selectorsIgnored[0] = target.reentrantCall.selector;
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        proxy.addReentrancyGuardSelectorsIgnored(selectorsIgnored);
    }

    function test_removeReentrancyGuardSelectorsIgnored_NonReentrantTestSelectorIgnored_Success() public {
        {
            bytes4[] memory selectorsIgnored = new bytes4[](3);
            selectorsIgnored[0] = target.nonReentrantCall.selector;
            selectorsIgnored[1] = target.reentrantCall.selector;
            selectorsIgnored[2] = target.callToNonReentrantStaticcall.selector;

            vm.prank(owner);
            proxy.addReentrancyGuardSelectorsIgnored(selectorsIgnored);
        }

        {
            bytes4[] memory selectorsIgnored = proxy.getReentrancyGuardSelectorsIgnored();
            assertEq(selectorsIgnored.length, 3);
            assertEq(selectorsIgnored[0], target.nonReentrantCall.selector);
            assertEq(selectorsIgnored[1], target.reentrantCall.selector);
            assertEq(selectorsIgnored[2], target.callToNonReentrantStaticcall.selector);
        }

        {
            bytes4[] memory selectorsIgnored = new bytes4[](1);
            selectorsIgnored[0] = target.reentrantCall.selector;

            vm.prank(owner);
            proxy.removeReentrancyGuardSelectorsIgnored(selectorsIgnored);
        }

        {
            bytes4[] memory selectorsIgnored = proxy.getReentrancyGuardSelectorsIgnored();
            assertEq(selectorsIgnored.length, 2);
            assertEq(selectorsIgnored[0], target.nonReentrantCall.selector);
            assertEq(selectorsIgnored[1], target.callToNonReentrantStaticcall.selector);
        }

        {
            bytes4[] memory selectorsIgnored = new bytes4[](2);
            selectorsIgnored[0] = target.nonReentrantCall.selector;
            selectorsIgnored[1] = target.callToNonReentrantStaticcall.selector;

            vm.prank(owner);
            proxy.removeReentrancyGuardSelectorsIgnored(selectorsIgnored);
        }

        {
            bytes4[] memory selectorsIgnored = proxy.getReentrancyGuardSelectorsIgnored();
            assertEq(selectorsIgnored.length, 0);
        }
    }

    function test_removeReentrancyGuardSelectorsIgnored_RevertIf_Not_Owner() public {
        bytes4[] memory selectorsIgnored = new bytes4[](1);
        selectorsIgnored[0] = target.reentrantCall.selector;
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        proxy.removeReentrancyGuardSelectorsIgnored(selectorsIgnored);
    }

    function test__lockReentrancyGuard_ForceLock_Revert() public {
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.expectRevert(IReentrancyGuard.ReentrancyGuard__ReentrantCall.selector);
        target.nonReentrantCall();
    }

    function test__unlockReentrancyGuard_ForceUnlock_Succeed() public {
        assertEq(target.x(), 0);
        vm.prank(owner);
        proxy.__lockReentrancyGuard();
        vm.prank(owner);
        proxy.__unlockReentrancyGuard();
        assertEq(target.nonReentrantCall(), 1);
    }

    fallback() external payable {}
}
