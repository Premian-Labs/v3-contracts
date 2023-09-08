// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";

contract Referral_SetRebateTier_Concrete_Test is Referral_Integration_Shared_Test {
    function test_setRebateTier_Success() public {
        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate1));
        changePrank(users.deployer);
        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);

        assertEq(uint8(referral.getRebateTier(users.referrer)), uint8(IReferral.RebateTier.PrimaryRebate2));
    }

    function test_setRebateTier_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.startPrank(users.trader);

        referral.setRebateTier(users.referrer, IReferral.RebateTier.PrimaryRebate2);
    }
}
