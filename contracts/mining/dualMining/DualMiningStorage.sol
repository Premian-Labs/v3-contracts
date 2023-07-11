// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IDualMining} from "./IDualMining.sol";

library DualMiningStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("premia.contracts.storage.DualMining");

    struct Layout {
        // The vault address for which this mining is
        address vault;
        // Timestamp at which reward distribution started
        uint256 startTimestamp;
        // Amount of rewards distributed per year
        UD60x18 rewardsPerYear;
        // Total rewards left to distribute
        UD60x18 rewardsAvailable;
        // Token used to pay rewards
        address rewardToken;
        // Decimals of rewardToken
        uint8 rewardTokenDecimals;
        // Total accumulated rewards allocated to this pool by parent mining contract (In reward token of parent mining contract)
        UD60x18 parentAccTotalRewards;
        // Total accumulated rewards allocated to this pool (In reward token of this mining contract)
        UD60x18 accTotalRewards;
        // `accRewardsPerShare` value of parent mining contract at initialization
        UD60x18 initialParentAccRewardsPerShare;
        // `accRewardsPerShare` value of parent mining contract when rewards ran out
        UD60x18 finalParentAccRewardsPerShare;
        // Last timestamp at which rewards have been updated
        uint256 lastRewardTimestamp;
        // User infos
        mapping(address user => IDualMining.UserInfo info) userInfo;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
