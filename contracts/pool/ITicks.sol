// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {Exposure} from "../libraries/Exposure.sol";

interface ITicks {
    struct TickData {
        uint256 price; // ToDo : Should not be required as we use price to index in the mapping
        int256 delta;
        Exposure.Data exposure;
    }

    function getInsertTicks(
        uint256 lower,
        uint256 upper,
        uint256 current
    ) external view returns (uint256 left, uint256 right);
}
