// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {Exposure} from "../libraries/Exposure.sol";

library Tick {
    using Exposure for Exposure.Data;

    struct Data {
        uint256 price; // ToDo : Should not be required as we use price to index in the mapping
        int256 delta;
        Exposure.Data exposure;
    }

    /**
     * @notice Move the market price across a Tick from left-to-right (right-to-left) and
     *         update both the Pool liquidity state and the Tick's external per liquidity
     *         values to account for the change.
     */
    function cross(Data memory self, Exposure.Data memory globalExposure)
        internal
        pure
        returns (Data memory)
    {
        self.delta = -self.delta; // Flip the tick
        self.exposure = globalExposure.sub(self.exposure);
        return self;
    }
}
