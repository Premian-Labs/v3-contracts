// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

import {ReferralStorage} from "./ReferralStorage.sol";

contract ReferralProxy is ProxyUpgradeableOwnable {
    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {
        ReferralStorage.Layout storage l = ReferralStorage.layout();

        l.primaryRebatePercents.push(UD60x18.wrap(0.05e18)); // 5%
        l.primaryRebatePercents.push(UD60x18.wrap(0.1e18)); // 10%
        l.primaryRebatePercents.push(UD60x18.wrap(0.2e18)); // 20%

        l.secondaryRebatePercent = UD60x18.wrap(0.1e18); // 10%
    }
}
