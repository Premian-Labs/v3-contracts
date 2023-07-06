// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IDualMining {
    error DualMining__NotAuthorized(address caller);

    struct UserInfo {
        uint256 lastUpdateTimestamp;
        // `accParentTotalRewards` value at last user update
        UD60x18 lastAccParentTotalRewards;
        // `accTotalRewards` value at last user update
        UD60x18 lastAccTotalRewards;
        // Total allocated unclaimed rewards
        UD60x18 reward;
    }

    /// @notice Add rewards to the contract
    function addRewards(UD60x18 amount) external;

    /// @notice Trigger an update for this mining pool
    function updatePool() external;

    /// @notice Trigger an update for a specific user
    function updateUser(address user, UD60x18 poolRewards, UD60x18 userRewards) external;

    /// @notice Claim rewards
    function claim() external;
}
