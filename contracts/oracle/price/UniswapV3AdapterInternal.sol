// SPDX-License-Identifier: GPL-2.0-or-later

// TODO:
pragma solidity >=0.8.7 <0.9.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {TokenSorting} from "../../libraries/TokenSorting.sol";

// TODO: remove IStaticOracle import
import {IStaticOracle} from "./IStaticOracle.sol";

import {IUniswapV3AdapterInternal} from "./IUniswapV3AdapterInternal.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";
import {OracleAdapterInternal} from "./OracleAdapterInternal.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract UniswapV3AdapterInternal is
    IUniswapV3AdapterInternal,
    OracleAdapterInternal
{
    using SafeCast for uint256;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    IStaticOracle internal immutable UNISWAP_V3_ORACLE;

    uint32 internal immutable MIN_PERIOD;
    uint32 internal immutable MAX_PERIOD;

    constructor(
        IStaticOracle uniswapV3Oracle,
        uint32 maxPeriod,
        uint32 minPeriod,
        uint32 initialPeriod
    ) {
        UNISWAP_V3_ORACLE = uniswapV3Oracle;

        MAX_PERIOD = maxPeriod;
        MIN_PERIOD = minPeriod;

        if (initialPeriod < MIN_PERIOD || initialPeriod > MAX_PERIOD)
            revert UniswapV3Adapter__InvalidPeriod(initialPeriod);

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        l.gasPerCardinality = 22_250;
        l.gasCostToSupportPool = 30_000;

        l.period = initialPeriod;
        emit PeriodChanged(initialPeriod);

        // Set cardinality, by using the oracle's default
        uint8 cardinality = UNISWAP_V3_ORACLE.CARDINALITY_PER_MINUTE();
        l.cardinalityPerMinute = cardinality;
        emit CardinalityPerMinuteChanged(cardinality);
    }

    function _upsertPair(
        address tokenA,
        address tokenB,
        bytes calldata
    ) internal {
        bytes32 pairKey = _keyForPair(tokenA, tokenB);
        address[] memory pools = _getAllPoolsSortedByLiquidity(tokenA, tokenB);

        if (pools.length == 0)
            revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        // Load to mem to avoid multiple storage reads
        address[] storage poolsForPair = l.poolsForPair[pairKey];
        uint256 cachedPoolsForPairLength = poolsForPair.length;
        uint256 preparedPoolCount;

        uint104 gasCostPerCardinality = l.gasPerCardinality;
        uint112 gasCostToSupportPool = l.gasCostToSupportPool;

        uint16 targetCardinality = uint16(
            (l.period * l.cardinalityPerMinute) / 60
        ) + 1;

        for (uint256 i; i < pools.length; i++) {
            address pool = pools[i];

            _tryIncreaseObservationCardinality(
                pool,
                targetCardinality,
                gasCostPerCardinality,
                gasCostToSupportPool
            );

            if (preparedPoolCount < cachedPoolsForPairLength) {
                // Rewrite storage
                poolsForPair[preparedPoolCount++] = pool;
            } else {
                // If I have more pools than before, then push
                poolsForPair.push(pool);
                preparedPoolCount++;
            }
        }

        if (preparedPoolCount == 0) revert UniswapV3Adapter__GasTooLow();

        // If I have less pools than before, then remove the extra pools
        for (uint256 i = preparedPoolCount; i < cachedPoolsForPairLength; i++) {
            poolsForPair.pop();
        }

        emit UpdatedPoolsForPair(tokenA, tokenB, poolsForPair);
    }

    function _getAllPoolsSortedByLiquidity(
        address tokenA,
        address tokenB
    ) internal view virtual returns (address[] memory) {
        address[] memory pools = UNISWAP_V3_ORACLE.getAllPoolsForPair(
            tokenA,
            tokenB
        );

        if (pools.length <= 1) return pools;

        // Store liquidity by pool
        uint128[] memory poolLiquidity = new uint128[](pools.length);
        for (uint256 i; i < pools.length; i++) {
            poolLiquidity[i] = IUniswapV3Pool(pools[i]).liquidity();
        }

        // TODO: call sorting algorithm function
        // Sort both arrays together
        for (uint256 i; i < pools.length - 1; i++) {
            uint256 biggestLiquidityIndex = i;

            for (uint256 j = i + 1; j < pools.length; j++) {
                if (poolLiquidity[j] > poolLiquidity[biggestLiquidityIndex]) {
                    biggestLiquidityIndex = j;
                }
            }

            if (biggestLiquidityIndex != i) {
                // Swap pools
                (pools[i], pools[biggestLiquidityIndex]) = (
                    pools[biggestLiquidityIndex],
                    pools[i]
                );

                // Don't need to swap both ways, can just move the liquidity in i to its new place
                poolLiquidity[biggestLiquidityIndex] = poolLiquidity[i];
            }
        }

        return pools;
    }

    function _tryIncreaseObservationCardinality(
        address pool,
        uint16 targetCardinality,
        uint104 gasCostPerCardinality,
        uint112 gasCostToSupportPool
    ) internal {
        (, , , , uint16 currentCardinality, , ) = IUniswapV3Pool(pool).slot0();

        if (currentCardinality < targetCardinality) {
            uint112 gasCostToIncreaseAndAddSupport = uint112(
                targetCardinality - currentCardinality
            ) *
                gasCostPerCardinality +
                gasCostToSupportPool;

            if (gasCostToIncreaseAndAddSupport <= gasleft()) {
                IUniswapV3Pool(pool).increaseObservationCardinalityNext(
                    targetCardinality
                );
            }
        }
    }

    function _keyForPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address _tokenA, address _tokenB) = TokenSorting.sortTokens(
            tokenA,
            tokenB
        );

        return keccak256(abi.encodePacked(_tokenA, _tokenB));
    }
}
