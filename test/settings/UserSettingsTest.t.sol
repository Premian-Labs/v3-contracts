// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";

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

    function _assertAllAuthorizationsFalse(address user, address operator) internal {
        (IUserSettings.Authorization[] memory authorizations, bool[] memory authorized) = settings.getAuthorizations(
            user,
            operator
        );

        assertEq(uint256(authorizations[0]), uint256(IUserSettings.Authorization.ANNIHILATE));
        assertEq(uint256(authorizations[1]), uint256(IUserSettings.Authorization.EXERCISE));
        assertEq(uint256(authorizations[2]), uint256(IUserSettings.Authorization.SETTLE));
        assertEq(uint256(authorizations[3]), uint256(IUserSettings.Authorization.SETTLE_POSITION));
        assertEq(uint256(authorizations[4]), uint256(IUserSettings.Authorization.WRITE_FROM));

        assertFalse(authorized[0]);
        assertFalse(authorized[1]);
        assertFalse(authorized[2]);
        assertFalse(authorized[3]);
        assertFalse(authorized[4]);
    }

    function _disableAllAuthorizations(address user, address operator) internal {
        IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](5);
        authorizations[0] = IUserSettings.Authorization.ANNIHILATE;
        authorizations[1] = IUserSettings.Authorization.EXERCISE;
        authorizations[2] = IUserSettings.Authorization.SETTLE;
        authorizations[3] = IUserSettings.Authorization.SETTLE_POSITION;
        authorizations[4] = IUserSettings.Authorization.WRITE_FROM;

        bool[] memory authorize = new bool[](5);
        authorize[0] = false;
        authorize[1] = false;
        authorize[2] = false;
        authorize[3] = false;
        authorize[4] = false;

        vm.prank(user);
        settings.setAuthorizations(operator, authorizations, authorize);
        _assertAllAuthorizationsFalse(user, operator);
    }

    function test_setAuthorizations_AuthorizationDefaultsToDisabled() public {
        assertFalse(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.ANNIHILATE));
        assertFalse(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.EXERCISE));
        assertFalse(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.SETTLE));
        assertFalse(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.SETTLE_POSITION));
        assertFalse(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.WRITE_FROM));

        assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.ANNIHILATE));
        assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.EXERCISE));
        assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.SETTLE));
        assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.SETTLE_POSITION));
        assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.WRITE_FROM));

        _assertAllAuthorizationsFalse(users.alice, users.operator);
        _assertAllAuthorizationsFalse(users.bob, users.operator);
    }

    function test_setAuthorizations_Success() public {
        {
            IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](5);
            authorizations[0] = IUserSettings.Authorization.ANNIHILATE;
            authorizations[1] = IUserSettings.Authorization.SETTLE;
            authorizations[2] = IUserSettings.Authorization.SETTLE_POSITION;
            authorizations[3] = IUserSettings.Authorization.WRITE_FROM;
            authorizations[4] = IUserSettings.Authorization.EXERCISE;

            bool[] memory authorize = new bool[](5);
            authorize[0] = true;
            authorize[1] = true;
            authorize[2] = true;
            authorize[3] = true;
            authorize[4] = true;

            vm.prank(users.alice);
            settings.setAuthorizations(users.operator, authorizations, authorize);

            assertTrue(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.ANNIHILATE));
            assertTrue(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.EXERCISE));
            assertTrue(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.SETTLE));
            assertTrue(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.SETTLE_POSITION));
            assertTrue(settings.isAuthorized(users.alice, users.operator, IUserSettings.Authorization.WRITE_FROM));
        }

        {
            IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](2);
            authorizations[0] = IUserSettings.Authorization.SETTLE;
            authorizations[1] = IUserSettings.Authorization.EXERCISE;

            bool[] memory authorize = new bool[](2);
            authorize[0] = true;
            authorize[1] = true;

            vm.prank(users.bob);
            settings.setAuthorizations(users.operator, authorizations, authorize);

            assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.ANNIHILATE));
            assertTrue(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.EXERCISE));
            assertTrue(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.SETTLE));
            assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.SETTLE_POSITION));
            assertFalse(settings.isAuthorized(users.bob, users.operator, IUserSettings.Authorization.WRITE_FROM));
        }

        {
            IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](5);
            authorizations[0] = IUserSettings.Authorization.WRITE_FROM;
            authorizations[1] = IUserSettings.Authorization.SETTLE_POSITION;
            // skips index 2
            authorizations[3] = IUserSettings.Authorization.ANNIHILATE;
            authorizations[4] = IUserSettings.Authorization.EXERCISE;

            bool[] memory authorize = new bool[](5);
            authorize[0] = false;
            authorize[1] = true;
            // skips index 2
            authorize[3] = false;
            authorize[4] = true;

            vm.prank(users.alice);
            settings.setAuthorizations(users.otherOperator, authorizations, authorize);

            assertFalse(
                settings.isAuthorized(users.alice, users.otherOperator, IUserSettings.Authorization.ANNIHILATE)
            );

            assertTrue(settings.isAuthorized(users.alice, users.otherOperator, IUserSettings.Authorization.EXERCISE));
            assertFalse(settings.isAuthorized(users.alice, users.otherOperator, IUserSettings.Authorization.SETTLE));

            assertTrue(
                settings.isAuthorized(users.alice, users.otherOperator, IUserSettings.Authorization.SETTLE_POSITION)
            );

            assertFalse(
                settings.isAuthorized(users.alice, users.otherOperator, IUserSettings.Authorization.WRITE_FROM)
            );
        }

        {
            (IUserSettings.Authorization[] memory authorizations, bool[] memory authorized) = settings
                .getAuthorizations(users.alice, users.operator);

            assertEq(uint256(authorizations[0]), uint256(IUserSettings.Authorization.ANNIHILATE));
            assertEq(uint256(authorizations[1]), uint256(IUserSettings.Authorization.EXERCISE));
            assertEq(uint256(authorizations[2]), uint256(IUserSettings.Authorization.SETTLE));
            assertEq(uint256(authorizations[3]), uint256(IUserSettings.Authorization.SETTLE_POSITION));
            assertEq(uint256(authorizations[4]), uint256(IUserSettings.Authorization.WRITE_FROM));

            assertTrue(authorized[0]);
            assertTrue(authorized[1]);
            assertTrue(authorized[2]);
            assertTrue(authorized[3]);
            assertTrue(authorized[4]);
        }

        {
            (IUserSettings.Authorization[] memory authorizations, bool[] memory authorized) = settings
                .getAuthorizations(users.bob, users.operator);

            assertEq(uint256(authorizations[0]), uint256(IUserSettings.Authorization.ANNIHILATE));
            assertEq(uint256(authorizations[1]), uint256(IUserSettings.Authorization.EXERCISE));
            assertEq(uint256(authorizations[2]), uint256(IUserSettings.Authorization.SETTLE));
            assertEq(uint256(authorizations[3]), uint256(IUserSettings.Authorization.SETTLE_POSITION));
            assertEq(uint256(authorizations[4]), uint256(IUserSettings.Authorization.WRITE_FROM));

            assertFalse(authorized[0]);
            assertTrue(authorized[1]);
            assertTrue(authorized[2]);
            assertFalse(authorized[3]);
            assertFalse(authorized[4]);
        }

        {
            (IUserSettings.Authorization[] memory authorizations, bool[] memory authorized) = settings
                .getAuthorizations(users.alice, users.otherOperator);

            assertEq(uint256(authorizations[0]), uint256(IUserSettings.Authorization.ANNIHILATE));
            assertEq(uint256(authorizations[1]), uint256(IUserSettings.Authorization.EXERCISE));
            assertEq(uint256(authorizations[2]), uint256(IUserSettings.Authorization.SETTLE));
            assertEq(uint256(authorizations[3]), uint256(IUserSettings.Authorization.SETTLE_POSITION));
            assertEq(uint256(authorizations[4]), uint256(IUserSettings.Authorization.WRITE_FROM));

            assertFalse(authorized[0]);
            assertTrue(authorized[1]);
            assertFalse(authorized[2]);
            assertTrue(authorized[3]);
            assertFalse(authorized[4]);
        }

        _disableAllAuthorizations(users.alice, users.operator);
        _disableAllAuthorizations(users.bob, users.operator);
        _disableAllAuthorizations(users.alice, users.otherOperator);
    }

    function test_setAuthorizations_RevertIf_InvalidArrayLength() public {
        {
            IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](1);
            bool[] memory authorize = new bool[](0);
            vm.expectRevert(IUserSettings.UserSettings__InvalidArrayLength.selector);
            settings.setAuthorizations(users.operator, authorizations, authorize);
        }

        {
            IUserSettings.Authorization[] memory authorizations = new IUserSettings.Authorization[](0);
            bool[] memory authorize = new bool[](1);
            vm.expectRevert(IUserSettings.UserSettings__InvalidArrayLength.selector);
            settings.setAuthorizations(users.operator, authorizations, authorize);
        }
    }

    function _test_setAuthorizedCost_Success() public {}
}
