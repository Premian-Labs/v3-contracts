// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

library Tick {
    // ToDo : Move somewhere else ?
    struct Data {
        int256 delta;
        uint256 externalFeeRate;
        int256 longDelta;
        int256 shortDelta;
        uint256 counter;
    }
}
