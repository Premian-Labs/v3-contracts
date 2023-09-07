// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";

contract Referral_UseReferral_Concrete_Test is Referral_Integration_Shared_Test {
    function test_useReferral_RevertIf_Pool_Not_Authorized() public {
        changePrank(users.trader);
        vm.expectRevert(IReferral.Referral__PoolNotAuthorized.selector);

        referral.useReferral(users.trader, users.referrer, address(0), ud(0), ud(0));
    }
}
