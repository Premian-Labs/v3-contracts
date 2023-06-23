// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

import {IUserSettings} from "contracts/settings/IUserSettings.sol";
import {UserSettings} from "contracts/settings/UserSettings.sol";

import {Assertions} from "../Assertions.sol";

contract UserSettingsTest is Test, Assertions {
    IUserSettings settings;

    Users users;

    struct Users {
        address alice;
        address bob;
        address operator;
        address otherOperator;
    }

    function setUp() public {
        users = Users({alice: vm.addr(1), bob: vm.addr(2), operator: vm.addr(3), otherOperator: vm.addr(4)});

        UserSettings userSettingsImpl = new UserSettings();
        ProxyUpgradeableOwnable userSettingsProxy = new ProxyUpgradeableOwnable(address(userSettingsImpl));
        settings = IUserSettings(address(userSettingsProxy));
    }

    function _assertAllAuthorizationFalse(address user, address operator) internal {
        (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
            user,
            operator
        );

        assertEq(uint256(actions[0]), uint256(IUserSettings.Action.ANNIHILATE));
        assertEq(uint256(actions[1]), uint256(IUserSettings.Action.EXERCISE));
        assertEq(uint256(actions[2]), uint256(IUserSettings.Action.SETTLE));
        assertEq(uint256(actions[3]), uint256(IUserSettings.Action.SETTLE_POSITION));
        assertEq(uint256(actions[4]), uint256(IUserSettings.Action.WRITE_FROM));

        assertFalse(authorization[0]);
        assertFalse(authorization[1]);
        assertFalse(authorization[2]);
        assertFalse(authorization[3]);
        assertFalse(authorization[4]);
    }

    function _disableAllAuthorization(address user, address operator) internal {
        IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
        actions[0] = IUserSettings.Action.ANNIHILATE;
        actions[1] = IUserSettings.Action.EXERCISE;
        actions[2] = IUserSettings.Action.SETTLE;
        actions[3] = IUserSettings.Action.SETTLE_POSITION;
        actions[4] = IUserSettings.Action.WRITE_FROM;

        bool[] memory authorization = new bool[](5);
        authorization[0] = false;
        authorization[1] = false;
        authorization[2] = false;
        authorization[3] = false;
        authorization[4] = false;

        vm.prank(user);
        settings.setActionAuthorization(operator, actions, authorization);
        _assertAllAuthorizationFalse(user, operator);
    }

    function test_setActionAuthorization_AuthorizationDefaultsToDisabled() public {
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.ANNIHILATE));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.EXERCISE));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SETTLE));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SETTLE_POSITION));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.WRITE_FROM));

        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.ANNIHILATE));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.EXERCISE));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SETTLE));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SETTLE_POSITION));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.WRITE_FROM));

        _assertAllAuthorizationFalse(users.alice, users.operator);
        _assertAllAuthorizationFalse(users.bob, users.operator);
    }

    function test_setActionAuthorization_Success() public {
        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
            actions[0] = IUserSettings.Action.ANNIHILATE;
            actions[1] = IUserSettings.Action.SETTLE;
            actions[2] = IUserSettings.Action.SETTLE_POSITION;
            actions[3] = IUserSettings.Action.WRITE_FROM;
            actions[4] = IUserSettings.Action.EXERCISE;

            bool[] memory authorization = new bool[](5);
            authorization[0] = true;
            authorization[1] = true;
            authorization[2] = true;
            authorization[3] = true;
            authorization[4] = true;

            vm.prank(users.alice);
            settings.setActionAuthorization(users.operator, actions, authorization);

            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.ANNIHILATE));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.EXERCISE));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SETTLE));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SETTLE_POSITION));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.WRITE_FROM));
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](2);
            actions[0] = IUserSettings.Action.SETTLE;
            actions[1] = IUserSettings.Action.EXERCISE;

            bool[] memory authorization = new bool[](2);
            authorization[0] = true;
            authorization[1] = true;

            vm.prank(users.bob);
            settings.setActionAuthorization(users.operator, actions, authorization);

            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.ANNIHILATE));
            assertTrue(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.EXERCISE));
            assertTrue(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SETTLE));
            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SETTLE_POSITION));
            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.WRITE_FROM));
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
            actions[0] = IUserSettings.Action.WRITE_FROM;
            actions[1] = IUserSettings.Action.SETTLE_POSITION;
            // skips index 2
            actions[3] = IUserSettings.Action.ANNIHILATE;
            actions[4] = IUserSettings.Action.EXERCISE;

            bool[] memory authorization = new bool[](5);
            authorization[0] = false;
            authorization[1] = true;
            // skips index 2
            authorization[3] = false;
            authorization[4] = true;

            vm.prank(users.alice);
            settings.setActionAuthorization(users.otherOperator, actions, authorization);

            assertFalse(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.ANNIHILATE));

            assertTrue(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.EXERCISE));
            assertFalse(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.SETTLE));

            assertTrue(
                settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.SETTLE_POSITION)
            );

            assertFalse(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.WRITE_FROM));
        }

        {
            (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
                users.alice,
                users.operator
            );

            assertEq(uint256(actions[0]), uint256(IUserSettings.Action.ANNIHILATE));
            assertEq(uint256(actions[1]), uint256(IUserSettings.Action.EXERCISE));
            assertEq(uint256(actions[2]), uint256(IUserSettings.Action.SETTLE));
            assertEq(uint256(actions[3]), uint256(IUserSettings.Action.SETTLE_POSITION));
            assertEq(uint256(actions[4]), uint256(IUserSettings.Action.WRITE_FROM));

            assertTrue(authorization[0]);
            assertTrue(authorization[1]);
            assertTrue(authorization[2]);
            assertTrue(authorization[3]);
            assertTrue(authorization[4]);
        }

        {
            (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
                users.bob,
                users.operator
            );

            assertEq(uint256(actions[0]), uint256(IUserSettings.Action.ANNIHILATE));
            assertEq(uint256(actions[1]), uint256(IUserSettings.Action.EXERCISE));
            assertEq(uint256(actions[2]), uint256(IUserSettings.Action.SETTLE));
            assertEq(uint256(actions[3]), uint256(IUserSettings.Action.SETTLE_POSITION));
            assertEq(uint256(actions[4]), uint256(IUserSettings.Action.WRITE_FROM));

            assertFalse(authorization[0]);
            assertTrue(authorization[1]);
            assertTrue(authorization[2]);
            assertFalse(authorization[3]);
            assertFalse(authorization[4]);
        }

        {
            (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
                users.alice,
                users.otherOperator
            );

            assertEq(uint256(actions[0]), uint256(IUserSettings.Action.ANNIHILATE));
            assertEq(uint256(actions[1]), uint256(IUserSettings.Action.EXERCISE));
            assertEq(uint256(actions[2]), uint256(IUserSettings.Action.SETTLE));
            assertEq(uint256(actions[3]), uint256(IUserSettings.Action.SETTLE_POSITION));
            assertEq(uint256(actions[4]), uint256(IUserSettings.Action.WRITE_FROM));

            assertFalse(authorization[0]);
            assertTrue(authorization[1]);
            assertFalse(authorization[2]);
            assertTrue(authorization[3]);
            assertFalse(authorization[4]);
        }

        _disableAllAuthorization(users.alice, users.operator);
        _disableAllAuthorization(users.bob, users.operator);
        _disableAllAuthorization(users.alice, users.otherOperator);
    }

    function test_setActionAuthorization_RevertIf_InvalidArrayLength() public {
        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
            bool[] memory authorization = new bool[](0);
            vm.expectRevert(IUserSettings.UserSettings__InvalidArrayLength.selector);
            settings.setActionAuthorization(users.operator, actions, authorization);
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](0);
            bool[] memory authorization = new bool[](1);
            vm.expectRevert(IUserSettings.UserSettings__InvalidArrayLength.selector);
            settings.setActionAuthorization(users.operator, actions, authorization);
        }
    }

    function test_setAuthorizedCost_Success() public {
        uint256 amountAlice = 1e18;
        vm.prank(users.alice);
        settings.setAuthorizedCost(amountAlice);

        uint256 amountBob = 10e18;
        vm.prank(users.bob);
        settings.setAuthorizedCost(amountBob);

        assertEq(settings.getAuthorizedCost(users.alice), amountAlice);
        assertEq(settings.getAuthorizedCost(users.bob), amountBob);

        amountAlice = 100e18;
        vm.prank(users.alice);
        settings.setAuthorizedCost(amountAlice);

        assertEq(settings.getAuthorizedCost(users.alice), amountAlice);
        assertEq(settings.getAuthorizedCost(users.bob), amountBob);
    }
}
