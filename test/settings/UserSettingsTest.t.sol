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

    function _assertActionsMatchExpected(IUserSettings.Action[] memory actions) internal {
        assertEq(actions.length, 5);
        assertEq(uint256(actions[0]), uint256(IUserSettings.Action.Annihilate));
        assertEq(uint256(actions[1]), uint256(IUserSettings.Action.Exercise));
        assertEq(uint256(actions[2]), uint256(IUserSettings.Action.Settle));
        assertEq(uint256(actions[3]), uint256(IUserSettings.Action.SettlePosition));
        assertEq(uint256(actions[4]), uint256(IUserSettings.Action.WriteFrom));
    }

    function _assertAllAuthorizationFalse(address user, address operator) internal {
        (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
            user,
            operator
        );

        _assertActionsMatchExpected(actions);

        assertEq(authorization.length, 5);
        assertFalse(authorization[0]);
        assertFalse(authorization[1]);
        assertFalse(authorization[2]);
        assertFalse(authorization[3]);
        assertFalse(authorization[4]);
    }

    function _disableAllAuthorization(address user, address operator) internal {
        IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
        actions[0] = IUserSettings.Action.Annihilate;
        actions[1] = IUserSettings.Action.Exercise;
        actions[2] = IUserSettings.Action.Settle;
        actions[3] = IUserSettings.Action.SettlePosition;
        actions[4] = IUserSettings.Action.WriteFrom;

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
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Annihilate));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Exercise));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Settle));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SettlePosition));
        assertFalse(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.WriteFrom));

        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Annihilate));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Exercise));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Settle));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SettlePosition));
        assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.WriteFrom));

        _assertAllAuthorizationFalse(users.alice, users.operator);
        _assertAllAuthorizationFalse(users.bob, users.operator);
    }

    function test_setActionAuthorization_Success() public {
        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
            actions[0] = IUserSettings.Action.Annihilate;
            actions[1] = IUserSettings.Action.Settle;
            actions[2] = IUserSettings.Action.SettlePosition;
            actions[3] = IUserSettings.Action.WriteFrom;
            actions[4] = IUserSettings.Action.Exercise;

            bool[] memory authorization = new bool[](5);
            authorization[0] = true;
            authorization[1] = true;
            authorization[2] = true;
            authorization[3] = true;
            authorization[4] = true;

            vm.prank(users.alice);
            settings.setActionAuthorization(users.operator, actions, authorization);

            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Annihilate));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Exercise));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.Settle));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.SettlePosition));
            assertTrue(settings.isActionAuthorized(users.alice, users.operator, IUserSettings.Action.WriteFrom));
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](2);
            actions[0] = IUserSettings.Action.Settle;
            actions[1] = IUserSettings.Action.Exercise;

            bool[] memory authorization = new bool[](2);
            authorization[0] = true;
            authorization[1] = true;

            vm.prank(users.bob);
            settings.setActionAuthorization(users.operator, actions, authorization);

            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Annihilate));
            assertTrue(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Exercise));
            assertTrue(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.Settle));
            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.SettlePosition));
            assertFalse(settings.isActionAuthorized(users.bob, users.operator, IUserSettings.Action.WriteFrom));
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](4);
            actions[0] = IUserSettings.Action.WriteFrom;
            actions[1] = IUserSettings.Action.SettlePosition;
            actions[2] = IUserSettings.Action.Annihilate;
            actions[3] = IUserSettings.Action.Exercise;

            bool[] memory authorization = new bool[](4);
            authorization[0] = false;
            authorization[1] = false;
            authorization[2] = true;
            authorization[3] = true;

            vm.prank(users.alice);
            settings.setActionAuthorization(users.otherOperator, actions, authorization);

            assertTrue(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.Annihilate));

            assertTrue(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.Exercise));
            assertFalse(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.Settle));

            assertFalse(
                settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.SettlePosition)
            );

            assertFalse(settings.isActionAuthorized(users.alice, users.otherOperator, IUserSettings.Action.WriteFrom));
        }

        {
            (IUserSettings.Action[] memory actions, bool[] memory authorization) = settings.getActionAuthorization(
                users.alice,
                users.operator
            );

            _assertActionsMatchExpected(actions);

            assertEq(authorization.length, 5);
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

            _assertActionsMatchExpected(actions);

            assertEq(authorization.length, 5);
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

            _assertActionsMatchExpected(actions);

            assertEq(authorization.length, 5);
            assertTrue(authorization[0]);
            assertTrue(authorization[1]);
            assertFalse(authorization[2]);
            assertFalse(authorization[3]);
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

    function test_setActionAuthorization_RevertIf_InvalidAction() public {
        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](1);
            actions[0] = IUserSettings.Action.__;

            bool[] memory authorization = new bool[](1);
            authorization[0] = true;

            vm.expectRevert(IUserSettings.UserSettings__InvalidAction.selector);
            settings.setActionAuthorization(users.operator, actions, authorization);
        }

        {
            IUserSettings.Action[] memory actions = new IUserSettings.Action[](5);
            actions[0] = IUserSettings.Action.WriteFrom;
            actions[1] = IUserSettings.Action.SettlePosition;
            actions[2] = IUserSettings.Action.Annihilate;
            // skip index 3
            actions[4] = IUserSettings.Action.Exercise;

            bool[] memory authorization = new bool[](5);
            authorization[0] = false;
            authorization[1] = false;
            authorization[2] = true;
            // skip index 3
            authorization[4] = true;

            vm.expectRevert(IUserSettings.UserSettings__InvalidAction.selector);
            settings.setActionAuthorization(users.operator, actions, authorization);
        }
    }

    function test_setAuthorizedCost_Success() public {
        UD60x18 amountAlice = ud(1e18);
        vm.prank(users.alice);
        settings.setAuthorizedCost(amountAlice);

        UD60x18 amountBob = ud(10e18);
        vm.prank(users.bob);
        settings.setAuthorizedCost(amountBob);

        assertEq(settings.getAuthorizedCost(users.alice), amountAlice);
        assertEq(settings.getAuthorizedCost(users.bob), amountBob);

        amountAlice = ud(100e18);
        vm.prank(users.alice);
        settings.setAuthorizedCost(amountAlice);

        assertEq(settings.getAuthorizedCost(users.alice), amountAlice);
        assertEq(settings.getAuthorizedCost(users.bob), amountBob);
    }
}
