// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IDualMining} from "./IDualMining.sol";

library DualMiningStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.DualMining");

    struct Layout {
        // Timestamp at which reward distribution starts
        // Users will start to accumulate rewards after their first user update past this timestamp
        uint256 startTimestamp;
        // Amount of rewards distributed per year
        UD60x18 rewardsPerYear;
        // Total rewards left to distribute
        UD60x18 rewardsAvailable;
        // Token used to pay rewards
        address rewardToken;
        uint8 rewardTokenDecimals;
        // Total accumulated rewards allocated to this pool by parent mining contract (In reward token of parent mining contract)
        UD60x18 accParentTotalRewards;
        // Total accumulated rewards allocated to this pool (In reward token of this mining contract)
        UD60x18 accTotalRewards;
        uint256 lastRewardTimestamp;
        mapping(address user => IDualMining.UserInfo info) userInfo;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
