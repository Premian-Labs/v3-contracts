// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IMiningAddRewards {
    /// @notice Add rewards to the mining contract
    function addRewards(uint256 amount) external;
}
