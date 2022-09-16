// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

library Exposure {
    using Exposure for Exposure.Data;

    struct Data {
        uint128 buyGrowthPerLiq;
        uint128 buyDecayPerLiq;
        uint128 sellGrowthPerLiq;
        uint128 sellDecayPerLiq;
        uint128 feesPerBuyLiq;
        uint128 feesPerSellLiq;
    }

    function add(Data memory self, Data memory other)
        internal
        pure
        returns (Data memory)
    {
        self.buyGrowthPerLiq += other.buyGrowthPerLiq;
        self.buyDecayPerLiq += other.buyDecayPerLiq;
        self.sellGrowthPerLiq += other.sellGrowthPerLiq;
        self.sellDecayPerLiq += other.sellDecayPerLiq;
        self.feesPerBuyLiq += other.feesPerBuyLiq;
        self.feesPerSellLiq += other.feesPerSellLiq;

        return self;
    }

    function sub(Data memory self, Data memory other)
        internal
        pure
        returns (Data memory)
    {
        self.buyGrowthPerLiq -= other.buyGrowthPerLiq;
        self.buyDecayPerLiq -= other.buyDecayPerLiq;
        self.sellGrowthPerLiq -= other.sellGrowthPerLiq;
        self.sellDecayPerLiq -= other.sellDecayPerLiq;
        self.feesPerBuyLiq -= other.feesPerBuyLiq;
        self.feesPerSellLiq -= other.feesPerSellLiq;

        return self;
    }
}
