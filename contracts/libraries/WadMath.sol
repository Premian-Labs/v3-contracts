// SPDX-License-Identifier: UNLICENSED



// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library WadMath {
    uint256 constant WAD = 1e18;

    function mulWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    function divWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * WAD) / b;
    }
}
