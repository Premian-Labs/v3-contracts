// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IReferral} from "../../referral/IReferral.sol";

interface IReferralMock is IReferral {
    function __trySetReferrer(address referrer) external returns (address cachedReferrer);
}
