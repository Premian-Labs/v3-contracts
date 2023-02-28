// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ChainlinkAdapterStorage} from "../../oracle/price/ChainlinkAdapterStorage.sol";

contract ChainlinkOraclePriceStub {
    uint16 PHASE_ID = 1;
    uint64 AGGREGATOR_ROUND_ID;

    uint256[] updatedAtTimestamps;
    int256[] prices;

    function setup(
        int256[] memory _prices,
        uint256[] memory _updatedAtTimestamps
    ) external {
        require(
            _prices.length == _updatedAtTimestamps.length,
            "length mismatch"
        );

        AGGREGATOR_ROUND_ID = uint64(_prices.length);

        prices = _prices;
        updatedAtTimestamps = _updatedAtTimestamps;
    }

    function price(uint256 index) external view returns (int256) {
        return prices[index];
    }

    function getRoundData(
        uint80 roundId
    ) external view returns (uint80, int256, uint256, uint256, uint80) {
        (, uint64 aggregatorRoundId) = ChainlinkAdapterStorage.parseRoundId(
            roundId
        );

        return (
            roundId,
            prices[aggregatorRoundId],
            0,
            updatedAtTimestamps[aggregatorRoundId],
            0
        );
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint80 roundId = ChainlinkAdapterStorage.formatRoundId(
            PHASE_ID,
            AGGREGATOR_ROUND_ID
        );
        uint64 aggregatorRoundId = AGGREGATOR_ROUND_ID - 1;

        return (
            roundId,
            prices[aggregatorRoundId],
            0,
            updatedAtTimestamps[aggregatorRoundId],
            0
        );
    }
}
