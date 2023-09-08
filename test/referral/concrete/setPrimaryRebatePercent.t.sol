// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral_Integration_Shared_Test} from "../shared/Referral.t.sol";
import {IReferral} from "contracts/referral/IReferral.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

contract Referral_SetPrimaryRebatePercent_Concrete_Test is Referral_Integration_Shared_Test {
    function test_setPrimaryRebatePercent_Success() public {
        UD60x18 percent = ud(100e18);

        changePrank(users.deployer);
        referral.setPrimaryRebatePercent(percent, IReferral.RebateTier.PrimaryRebate1);

        (UD60x18[] memory primaryRebatePercents, ) = referral.getRebatePercents();

        assertEq(primaryRebatePercents[0], percent);
    }

    function test_setPrimaryRebatePercent_RevertIf_Not_Owner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.startPrank(users.trader);

        referral.setPrimaryRebatePercent(ud(100e18), IReferral.RebateTier.PrimaryRebate1);
    }
}
