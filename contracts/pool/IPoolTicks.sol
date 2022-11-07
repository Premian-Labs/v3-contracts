// SPDX-License-Identifier: UNLICENSED

// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

interface IPoolTicks {
    function getInsertTicks(
        uint256 lower,
        uint256 upper,
        uint256 current
    ) external view returns (uint256 left, uint256 right);
}
