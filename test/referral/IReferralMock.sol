// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {IReferral} from "contracts/referral/IReferral.sol";

interface IReferralMock is IReferral {
    function __trySetReferrer(address referrer) external returns (address cachedReferrer);
}
