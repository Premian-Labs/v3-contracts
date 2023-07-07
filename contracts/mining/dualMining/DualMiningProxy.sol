// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

import {DualMiningStorage} from "./DualMiningStorage.sol";

contract DualMiningProxy is ProxyUpgradeableOwnable {
    constructor(
        address implementation,
        address rewardToken,
        UD60x18 rewardsPerYear
    ) ProxyUpgradeableOwnable(implementation) {
        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        l.rewardsPerYear = rewardsPerYear;
        l.rewardToken = rewardToken;
        l.rewardTokenDecimals = IERC20Metadata(rewardToken).decimals();
    }
}
