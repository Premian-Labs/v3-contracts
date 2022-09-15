// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface ITicks {
    struct TickData {
        uint256 price;
        int256 delta;
        // ToDo : Probably need to do some packing if we need all those here -> See precision required
        uint256 externalBuyGrowthPerLiq;
        uint256 externalBuyDecayPerLiq;
        uint256 externalSellGrowthPerLiq;
        uint256 externalSellDecayPerLiq;
        uint256 externalFeePerSellLiq;
        uint256 externalFeePerBuyLiq;
    }

    function getInsertTicks(
        uint256 lower,
        uint256 upper,
        uint256 current
    ) external view returns (uint256 left, uint256 right);
}
