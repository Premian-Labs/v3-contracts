// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import {IUniswapV3AdapterInternal} from "./IUniswapV3AdapterInternal.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";
import {SafeCast, TokenSorting, OracleAdapterInternal} from "./OracleAdapterInternal.sol";

import "hardhat/console.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles and
///         https://github.com/Mean-Finance/uniswap-v3-oracle
contract UniswapV3AdapterInternal is
    IUniswapV3AdapterInternal,
    OracleAdapterInternal
{
    using SafeCast for uint256;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    IUniswapV3Factory internal immutable UNISWAP_V3_FACTORY;

    /// @dev init bytecode from the deployed version of Uniswap V3 Pool contract
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    constructor(IUniswapV3Factory uniswapV3Factory) {
        UNISWAP_V3_FACTORY = uniswapV3Factory;
    }

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint32 target
    ) internal view returns (uint256) {
        // TODO: Period Validation
        // TODO: Cardinality Validation

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory pools = _poolsForPair(tokenIn, tokenOut);

        if (pools.length == 0) {
            pools = _tryFindPools(l, tokenIn, tokenOut);
        }

        uint32 period = l.period;
        uint32[] memory range = _calculateRange(period, target);

        OracleLibrary.WeightedTickData[] memory tickData = target == 0
            ? _fetchTickData(pools, range)
            : _fetchTickDataFrom(pools, period, range, target);

        int24 weightedTick = tickData.length == 1
            ? tickData[0].tick
            : OracleLibrary.getWeightedArithmeticMeanTick(tickData);

        int256 factor = _decimals(tokenIn) - _decimals(tokenOut);

        // TODO: Price validation
        // TODO: Try calculating price without using `getQuoteAtTick`

        return
            _scale(
                OracleLibrary.getQuoteAtTick(
                    weightedTick,
                    uint128(ONE_ETH),
                    tokenIn,
                    tokenOut
                ),
                factor
            );
    }

    function _fetchTickData(
        address[] memory pools,
        uint32[] memory range
    ) internal view returns (OracleLibrary.WeightedTickData[] memory) {
        OracleLibrary.WeightedTickData[]
            memory tickData = new OracleLibrary.WeightedTickData[](
                pools.length
            );

        for (uint256 i; i < pools.length; i++) {
            (tickData[i].tick, tickData[i].weight) = _consult(pools[i], range);
        }

        return tickData;
    }

    function _fetchTickDataFrom(
        address[] memory pools,
        uint32 period,
        uint32[] memory range,
        uint32 target
    ) internal view returns (OracleLibrary.WeightedTickData[] memory) {
        OracleLibrary.WeightedTickData[]
            memory tickData = new OracleLibrary.WeightedTickData[](
                pools.length
            );

        for (uint256 i; i < pools.length; i++) {
            (tickData[i].tick, tickData[i].weight) = _consult(pools[i], range);
        }

        return tickData;
    }

    function _calculateRange(
        uint32 period,
        uint32 target
    ) internal view returns (uint32[] memory) {
        uint32[] memory range = new uint32[](2);

        range[0] = period;
        range[1] = 0;

        if (target > 0) {
            uint32 midPoint = (period / 2);
            uint32 blockTimestamp = block.timestamp.toUint32();

            range[0] = blockTimestamp - (target - midPoint);

            uint32 delta = target + midPoint;

            range[1] = delta >= blockTimestamp
                ? blockTimestamp
                : blockTimestamp - delta;
        }

        return range;
    }

    function _tryFindPools(
        UniswapV3AdapterStorage.Layout storage l,
        address tokenIn,
        address tokenOut
    ) internal view returns (address[] memory) {
        address[] memory pools = _getPoolsSortedByLiquidity(tokenIn, tokenOut);
        uint256 poolLength = pools.length;

        if (poolLength == 0)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        uint16 targetCardinality = uint16(
            (l.period * l.cardinalityPerMinute) / 60
        ) + 1;

        for (uint256 i; i < poolLength; i++) {
            address pool = pools[i];

            (bool increaseCardinality, ) = _increaseCardinality(
                pool,
                targetCardinality
            );

            if (increaseCardinality)
                revert UniswapV3Adapter__ObservationCardinalityTooLow();
        }

        return pools;
    }

    function _getPoolsSortedByLiquidity(
        address tokenA,
        address tokenB
    ) internal view returns (address[] memory) {
        address[] memory pools = _getAllPoolsForPair(tokenA, tokenB);
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

    function _getAllPoolsForPair(
        address tokenA,
        address tokenB
    ) internal view returns (address[] memory pools) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        uint24[] memory knownFeeTiers = l.knownFeeTiers;

        pools = new address[](knownFeeTiers.length);
        uint256 validPools;

        for (uint256 i; i < knownFeeTiers.length; i++) {
            address pool = _computeAddress(
                address(UNISWAP_V3_FACTORY),
                PoolAddress.getPoolKey(tokenA, tokenB, knownFeeTiers[i])
            );

            if (AddressUtils.isContract(pool)) {
                pools[validPools++] = pool;
            }
        }

        _resizeArray(pools, validPools);
    }

    function _resizeArray(
        address[] memory array,
        uint256 amountOfValidElements
    ) internal pure {
        // If all elements are valid, then nothing to do here
        if (array.length == amountOfValidElements) return;

        // If not, then resize the array
        assembly {
            mstore(array, amountOfValidElements)
        }
    }

    function _increaseCardinality(
        address pool,
        uint16 targetCardinality,
        uint104 gasCostPerCardinality,
        uint112 gasCostToSupportPool
    ) internal {
        (
            bool increaseCardinality,
            uint16 currentCardinality
        ) = _increaseCardinality(pool, targetCardinality);

        if (increaseCardinality) {
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

    function _increaseCardinality(
        address pool,
        uint16 targetCardinality
    ) internal view returns (bool, uint16) {
        (, , , , uint16 currentCardinality, , ) = IUniswapV3Pool(pool).slot0();
        return (currentCardinality < targetCardinality, currentCardinality);
    }

    function _poolsForPair(
        address tokenA,
        address tokenB
    ) internal view returns (address[] storage) {
        return
            UniswapV3AdapterStorage.layout().poolsForPair[
                _keyForUnsortedPair(tokenA, tokenB)
            ];
    }

    function _decimals(address token) internal view returns (int256) {
        return int256(uint256(IERC20Metadata(token).decimals()));
    }

    /// @dev https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/libraries/PoolAddress.sol#L33-L49
    ///      This function has been modified to query any range of times
    function _consult(
        address pool,
        uint32[] memory range
    )
        internal
        view
        returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity)
    {
        if (range.length != 2 || range[0] <= range[1])
            revert UniswapV3Adapter__InvalidTimeRange();

        uint32 span = range[0] - range[1];

        (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) = IUniswapV3Pool(pool).observe(range);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        uint160 secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[
                1
            ] - secondsPerLiquidityCumulativeX128s[0];

        arithmeticMeanTick = int24(tickCumulativesDelta / int56(uint56(span)));
        // Always round to negative infinity
        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % int56(uint56(span)) != 0)
        ) arithmeticMeanTick--;

        // We are multiplying here instead of shifting to ensure that harmonicMeanLiquidity doesn't overflow uint128
        uint192 secondsAgoX160 = uint192(span) * type(uint160).max;

        harmonicMeanLiquidity = uint128(
            secondsAgoX160 /
                (uint192(secondsPerLiquidityCumulativesDelta) << 32)
        );
    }

    /// @dev https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/PoolAddress.sol#L33-L47
    ///      This function uses the POOL_INIT_CODE_HASH from the deployed version of Uniswap V3 Pool contract
    function _computeAddress(
        address factory,
        PoolAddress.PoolKey memory key
    ) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(
                                abi.encode(key.token0, key.token1, key.fee)
                            ),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
