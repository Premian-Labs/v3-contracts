// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library Tick {
    struct Data {
        uint256 price; // ToDo : Should not be required as we use price to index in the mapping
        int256 delta;
        uint256 externalFeesPerLiq;
    }

    /**
     * @notice Move the market price across a Tick from left-to-right (right-to-left) and
     *         update both the Pool liquidity state and the Tick's external per liquidity
     *         values to account for the change.
     */
    function cross(Data memory self, uint256 globalFeesPerLiq)
        internal
        pure
        returns (Data memory)
    {
        self.delta = -self.delta; // Flip the tick
        self.externalFeesPerLiq = globalFeesPerLiq - self.externalFeesPerLiq;
        return self;
    }
}
