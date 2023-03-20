// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IUniswapV3Factory} from "../../vendor/uniswap/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../vendor/uniswap/IUniswapV3Pool.sol";
import {OracleLibrary} from "../../vendor/uniswap/OracleLibrary.sol";
import {PoolAddress} from "../../vendor/uniswap/PoolAddress.sol";

import {IUniswapV3AdapterInternal} from "./IUniswapV3AdapterInternal.sol";
import {OracleAdapterInternal} from "./OracleAdapterInternal.sol";
import {ETH_DECIMALS, Tokens} from "./Tokens.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

contract UniswapV3AdapterInternal is
    IUniswapV3AdapterInternal,
    OracleAdapterInternal
{
    using SafeCast for uint256;
    using Tokens for address;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    IUniswapV3Factory internal immutable UNISWAP_V3_FACTORY;

    /// @dev init bytecode from the deployed version of Uniswap V3 Pool contract
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint256 internal immutable GAS_PER_CARDINALITY;
    uint256 internal immutable GAS_TO_SUPPORT_POOL;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        uint256 gasPerCardinality,
        uint256 gasToSupportPool
    ) {
        UNISWAP_V3_FACTORY = uniswapV3Factory;
        GAS_PER_CARDINALITY = gasPerCardinality;
        GAS_TO_SUPPORT_POOL = gasToSupportPool;
    }

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint32 target
    ) internal view returns (uint256) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory pools = _poolsForPair(tokenIn, tokenOut);

        if (pools.length == 0) {
            pools = _tryFindPools(l, tokenIn, tokenOut);
        }

        int24 weightedTick = _fetchWeightedTick(pools, l.period, target);

        int256 factor = ETH_DECIMALS - _decimals(tokenOut);

        uint256 price = _scale(
            OracleLibrary.getQuoteAtTick(
                weightedTick,
                uint128(10 ** uint256(_decimals(tokenIn))),
                tokenIn,
                tokenOut
            ),
            factor
        );

        _ensurePricePositive(price.toInt256());
        return price;
    }

    function _fetchWeightedTick(
        address[] memory pools,
        uint32 period,
        uint32 target
    ) internal view returns (int24) {
        OracleLibrary.WeightedTickData[]
            memory tickData = new OracleLibrary.WeightedTickData[](
                pools.length
            );

        for (uint256 i; i < pools.length; i++) {
            uint32[] memory range = _calculateRange(pools[i], period, target);
            (tickData[i].tick, tickData[i].weight) = _consult(pools[i], range);
        }

        return
            tickData.length == 1
                ? tickData[0].tick
                : OracleLibrary.getWeightedArithmeticMeanTick(tickData);
    }

    function _calculateRange(
        address pool,
        uint32 period,
        uint32 target
    ) internal view returns (uint32[] memory) {
        uint32[] memory range = new uint32[](2);

        range[0] = period;
        range[1] = 0;

        uint32 blockTimestamp = block.timestamp.toUint32();

        if (target > 0) {
            range[0] = blockTimestamp - (target - period); // rangeStart
            range[1] = blockTimestamp - target; // rangeEnd
        }

        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(
            pool
        );

        if (range[0] > oldestObservation) {
            // When the oldest obersvation is before the range start, restart range
            // from oldest obeservation
            //
            //  end                 target   oldest         start
            //   |                    v        |              |
            //   |--|--|--|--|--|--|--o--|--|--|///////////|--|
            //            ^           ^
            //        rangeStart   rangeEnd

            if (oldestObservation < period)
                revert UniswapV3Adapter__InsufficientObservationPeriod();

            range[0] = oldestObservation;
            range[1] = oldestObservation - period;
        }

        return range;
    }

    function _tryFindPools(
        UniswapV3AdapterStorage.Layout storage l,
        address tokenIn,
        address tokenOut
    ) internal view returns (address[] memory) {
        address[] memory pools = _getAllPoolsForPair(tokenIn, tokenOut);
        uint256 poolLength = pools.length;

        if (poolLength == 0)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        for (uint256 i; i < poolLength; i++) {
            address pool = pools[i];

            (
                bool currentCardinalityBelowTarget,

            ) = _isCurrentCardinalityBelowTarget(pool, l.targetCardinality);

            if (currentCardinalityBelowTarget)
                revert UniswapV3Adapter__ObservationCardinalityTooLow();
        }

        return pools;
    }

    function _getAllPoolsForPair(
        address tokenA,
        address tokenB
    ) internal view returns (address[] memory pools) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        uint24[] memory feeTiers = l.feeTiers;

        pools = new address[](feeTiers.length);
        uint256 validPools;

        for (uint256 i; i < feeTiers.length; i++) {
            address pool = _computeAddress(
                address(UNISWAP_V3_FACTORY),
                PoolAddress.getPoolKey(tokenA, tokenB, feeTiers[i])
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

    function _tryIncreaseCardinality(
        address pool,
        uint16 targetCardinality
    ) internal {
        (
            bool currentCardinalityBelowTarget,
            uint16 currentCardinality
        ) = _isCurrentCardinalityBelowTarget(pool, targetCardinality);

        if (!currentCardinalityBelowTarget) return;

        uint256 gasCostToIncreaseAndAddSupport = (targetCardinality -
            currentCardinality) *
            GAS_PER_CARDINALITY +
            GAS_TO_SUPPORT_POOL;

        if (gasCostToIncreaseAndAddSupport <= gasleft()) {
            IUniswapV3Pool(pool).increaseObservationCardinalityNext(
                targetCardinality
            );
        } else {
            // If the cardinality cannot be increased due to gas cost, revert
            revert UniswapV3Adapter__ObservationCardinalityTooLow();
        }
    }

    function _isCurrentCardinalityBelowTarget(
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
                tokenA.keyForUnsortedPair(tokenB)
            ];
    }

    function _decimals(address token) internal view returns (int256) {
        return int256(uint256(IERC20Metadata(token).decimals()));
    }

    /// @dev https://github.com/Uniswap/v3-periphery/blob/0.8/contracts/libraries/OracleLibrary.sol#L16-L41
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
