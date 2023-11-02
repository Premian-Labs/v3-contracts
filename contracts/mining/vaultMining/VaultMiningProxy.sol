// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {VaultMiningStorage} from "./VaultMiningStorage.sol";
import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

contract VaultMiningProxy is ProxyUpgradeableOwnable {
    constructor(address implementation, UD60x18 rewardsPerYear) ProxyUpgradeableOwnable(implementation) {
        VaultMiningStorage.Layout storage l = VaultMiningStorage.layout();

        l.lastUpdate = block.timestamp;
        l.rewardsPerYear = rewardsPerYear;
    }
}
