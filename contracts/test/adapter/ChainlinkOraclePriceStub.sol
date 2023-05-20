// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {ChainlinkAdapterStorage} from "../../adapter/chainlink/ChainlinkAdapterStorage.sol";

contract ChainlinkOraclePriceStub {
    uint16 internal PHASE_ID = 1;
    uint64 internal AGGREGATOR_ROUND_ID;

    uint256[] internal updatedAtTimestamps;
    int256[] internal prices;

    FailureMode internal failureMode;

    enum FailureMode {
        NONE,
        GET_ROUND_DATA_REVERT_WITH_REASON,
        GET_ROUND_DATA_REVERT,
        LAST_ROUND_DATA_REVERT_WITH_REASON,
        LAST_ROUND_DATA_REVERT
    }

    function setup(
        FailureMode _failureMode,
        int256[] memory _prices,
        uint256[] memory _updatedAtTimestamps
    ) external {
        failureMode = _failureMode;

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

        if (failureMode == FailureMode.GET_ROUND_DATA_REVERT_WITH_REASON) {
            require(false, "reverted with reason");
        }

        if (failureMode == FailureMode.GET_ROUND_DATA_REVERT) {
            revert();
        }

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

        if (failureMode == FailureMode.LAST_ROUND_DATA_REVERT_WITH_REASON) {
            require(false, "reverted with reason");
        }

        if (failureMode == FailureMode.LAST_ROUND_DATA_REVERT) {
            revert();
        }

        return (
            roundId,
            prices[aggregatorRoundId],
            0,
            updatedAtTimestamps[aggregatorRoundId],
            0
        );
    }
}
