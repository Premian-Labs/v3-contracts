// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";

contract Referral_Internal_TrySetReferrer_Concrete_Test is Referral_Integration_Shared_Test {
    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Not_Set() public {
        vm.startPrank(users.trader);
        address referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, address(0));
        assertEq(referral.getReferrer(users.trader), address(0));
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Not_Set() public {
        vm.startPrank(users.trader);
        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);
        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_No_Referrer_Provided_Referrer_Set() public {
        vm.startPrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(address(0));
        assertEq(referrer, users.referrer);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
    }

    function test_internal_trySetReferrer_Referrer_Provided_Referrer_Set() public {
        vm.startPrank(users.trader);

        address referrer = referral.__trySetReferrer(users.referrer);
        assertEq(referrer, users.referrer);

        referrer = referral.__trySetReferrer(secondaryReferrer);
        assertEq(referrer, users.referrer);

        vm.stopPrank();

        assertEq(referral.getReferrer(users.trader), users.referrer);
    }
}
