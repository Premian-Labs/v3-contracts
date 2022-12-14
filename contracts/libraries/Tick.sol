// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Tick {
    struct Data {
        int256 delta;
        uint256 externalFeeRate;
    }

    /// @notice Crosses the active tick either to the left if the LT is selling
    ///         to the pool. A cross is only executed if no bid or ask liquidity is
    ///         remaining within the active tick range.
    function cross(
        Data memory self,
        uint256 globalFeeRate
    ) internal pure returns (Data memory) {
        self.delta = -self.delta; // Flip the tick
        self.externalFeeRate = globalFeeRate - self.externalFeeRate;
        return self;
    }
}
