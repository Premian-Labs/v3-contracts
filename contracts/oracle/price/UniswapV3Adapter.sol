// SPDX-License-Identifier: GPL-2.0-or-later

// TODO:
pragma solidity >=0.8.7 <0.9.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IStaticOracle} from "./IStaticOracle.sol";
import {IUniswapV3Adapter} from "./IUniswapV3Adapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";
import {UniswapV3AdapterInternal} from "./UniswapV3AdapterInternal.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract UniswapV3Adapter is
    IUniswapV3Adapter,
    OracleAdapter,
    SafeOwnable,
    UniswapV3AdapterInternal
{
    using SafeCast for uint256;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    constructor(
        IStaticOracle uniswapV3Oracle,
        uint32 maxPeriod,
        uint32 minPeriod,
        uint32 initialPeriod
    )
        UniswapV3AdapterInternal(
            uniswapV3Oracle,
            maxPeriod,
            minPeriod,
            initialPeriod
        )
    {}

    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool) {
        return
            UniswapV3AdapterStorage
                .layout()
                .poolsForPair[_keyForPair(tokenA, tokenB)]
                .length > 0;
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut,
        bytes calldata
    ) external view returns (uint256) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory pools = l.poolsForPair[_keyForPair(tokenIn, tokenOut)];

        if (pools.length == 0)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        // TODO Remove amountIn
        return
            UNISWAP_V3_ORACLE.quoteSpecificPoolsWithTimePeriod(
                0,
                tokenIn,
                tokenOut,
                pools,
                l.period
            );
    }

    /// @inheritdoc IUniswapV3Adapter
    function getPoolsPreparedForPair(
        address tokenA,
        address tokenB
    ) external view returns (address[] memory) {
        return
            UniswapV3AdapterStorage.layout().poolsForPair[
                _keyForPair(tokenA, tokenB)
            ];
    }

    /// @inheritdoc IUniswapV3Adapter
    function setPeriod(uint32 newPeriod) external onlyOwner {
        if (newPeriod < MIN_PERIOD || newPeriod > MAX_PERIOD)
            revert UniswapV3Adapter__InvalidPeriod(newPeriod);

        UniswapV3AdapterStorage.layout().period = newPeriod;
        emit PeriodChanged(newPeriod);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setCardinalityPerMinute(
        uint8 cardinalityPerMinute
    ) external onlyOwner {
        if (cardinalityPerMinute == 0)
            revert UniswapV3Adapter__InvalidCardinalityPerMinute();

        UniswapV3AdapterStorage
            .layout()
            .cardinalityPerMinute = cardinalityPerMinute;

        emit CardinalityPerMinuteChanged(cardinalityPerMinute);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setGasPerCardinality(
        uint104 gasPerCardinality
    ) external onlyOwner {
        if (gasPerCardinality == 0)
            revert UniswapV3Adapter__InvalidGasPerCardinality();

        UniswapV3AdapterStorage.layout().gasPerCardinality = gasPerCardinality;
        emit GasPerCardinalityChanged(gasPerCardinality);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setGasCostToSupportPool(
        uint112 gasCostToSupportPool
    ) external onlyOwner {
        if (gasCostToSupportPool == 0)
            revert UniswapV3Adapter__InvalidGasCostToSupportPool();

        UniswapV3AdapterStorage
            .layout()
            .gasCostToSupportPool = gasCostToSupportPool;

        emit GasCostToSupportPoolChanged(gasCostToSupportPool);
    }
}
