// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Referral} from "../../referral/Referral.sol";

import {IReferralMock} from "./IReferralMock.sol";

contract ReferralMock is IReferralMock, Referral {
    constructor(address factory) Referral(factory) {}

    function __trySetReferrer(address referrer) external returns (address) {
        return _trySetReferrer(msg.sender, referrer);
    }
}
