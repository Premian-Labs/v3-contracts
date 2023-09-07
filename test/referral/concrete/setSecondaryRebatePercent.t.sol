// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

contract Referral_SetSecondaryRebatePercent_Concrete_Test is Referral_Integration_Shared_Test {
    // Below test not passing, somehting on Referral.setSecondaryRebatePercent Line pretaining to gas
    function test_setSecondaryRebatePercent_Success() public {
        UD60x18 percent = ud(100e18);
        changePrank(users.deployer);
        referral.setSecondaryRebatePercent(percent);

        (, UD60x18 secondaryRebatePercent) = referral.getRebatePercents();

        assertEq(secondaryRebatePercent, percent);
    }

    function test_setSecondaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.startPrank(users.trader);
        referral.setSecondaryRebatePercent(ud(100e18));
    }
}
