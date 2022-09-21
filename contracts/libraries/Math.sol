// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library Math {
    using Math for int256;

    function abs(int256 self) internal pure returns (uint256) {
        return self < 0 ? uint256(-self) : uint256(self);
    }

    function addInt256(uint256 self, int256 other)
        internal
        pure
        returns (uint256)
    {
        return self - other.abs();
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}
