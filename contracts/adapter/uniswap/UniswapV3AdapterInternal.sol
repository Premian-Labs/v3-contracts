// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import {OracleAdapterInternal} from "../OracleAdapterInternal.sol";
import {ETH_DECIMALS, Tokens} from "../Tokens.sol";

import {IUniswapV3AdapterInternal} from "./IUniswapV3AdapterInternal.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

contract UniswapV3AdapterInternal is
    IUniswapV3AdapterInternal,
    OracleAdapterInternal
{
    using SafeCast for uint256;
    using Tokens for address;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    IUniswapV3Factory internal immutable UNISWAP_V3_FACTORY;
    address internal immutable WRAPPED_NATIVE_TOKEN;

    /// @dev init bytecode from the deployed version of Uniswap V3 Pool contract
    bytes32 internal constant POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    uint256 internal immutable GAS_PER_CARDINALITY;
    uint256 internal immutable GAS_TO_SUPPORT_POOL;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        address wrappedNativeToken,
        uint256 gasPerCardinality,
        uint256 gasToSupportPool
    ) {
        UNISWAP_V3_FACTORY = uniswapV3Factory;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        GAS_PER_CARDINALITY = gasPerCardinality;
        GAS_TO_SUPPORT_POOL = gasToSupportPool;
    }

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory pools = _poolsForPair(tokenIn, tokenOut);
        address[] memory allDeployedPools = _getAllPoolsForPair(
            tokenIn,
            tokenOut
        );

        if (allDeployedPools.length == 0)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        /// if a pool has been deployed but not added to the adapter, we may use it for the quote
        /// only if it has sufficient cardinality.
        if (pools.length == 0 || pools.length < allDeployedPools.length) {
            _validatePoolCardinality(l, allDeployedPools);
            pools = allDeployedPools;
        }

        int24 weightedTick = _fetchWeightedTick(pools, l.period, target);
        int8 factor = int8(ETH_DECIMALS) - int8(_decimals(tokenOut));

        UD60x18 price = UD60x18.wrap(
            _scale(
                OracleLibrary.getQuoteAtTick(
                    weightedTick,
                    (10 ** uint256(_decimals(tokenIn))).toUint128(),
                    tokenIn,
                    tokenOut
                ),
                factor
            )
        );

        _ensurePricePositive(price.intoSD59x18().unwrap());
        return price;
    }

    function _fetchWeightedTick(
        address[] memory pools,
        uint32 period,
        uint256 target
    ) internal view returns (int24) {
        OracleLibrary.WeightedTickData[]
            memory tickData = new OracleLibrary.WeightedTickData[](
                pools.length
            );

        for (uint256 i = 0; i < pools.length; i++) {
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
        uint256 target
    ) internal view returns (uint32[] memory) {
        uint32[] memory range = new uint32[](2);

        if (target > 0) {
            range[0] = (block.timestamp - (target - period)).toUint32(); // rangeStart
            range[1] = (block.timestamp - target).toUint32(); // rangeEnd
        } else {
            range[0] = period;
            range[1] = 0;
        }

        uint32 oldestObservation = OracleLibrary.getOldestObservationSecondsAgo(
            pool
        );

        if (range[0] > oldestObservation) {
            // When the oldest observation is before the range start, restart range
            // from oldest observation
            //
            //  end                 target   oldest         start
            //   |                    v        |              |
            //   |--|--|--|--|--|--|--o--|--|--|///////////|--|
            //            ^           ^
            //        rangeStart   rangeEnd

            if (oldestObservation < period)
                revert UniswapV3Adapter__InsufficientObservationPeriod(
                    oldestObservation,
                    period
                );

            range[0] = oldestObservation;
            range[1] = oldestObservation - period;
        }

        return range;
    }

    function _validatePoolCardinality(
        UniswapV3AdapterStorage.Layout storage l,
        address[] memory pools
    ) internal view {
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];

            (
                bool currentCardinalityBelowTarget,
                uint16 currentCardinality
            ) = _isCurrentCardinalityBelowTarget(pool, l.targetCardinality);

            if (currentCardinalityBelowTarget)
                revert UniswapV3Adapter__ObservationCardinalityTooLow(
                    currentCardinality,
                    l.targetCardinality
                );
        }
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

        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = _computeAddress(
                address(UNISWAP_V3_FACTORY),
                PoolAddress.getPoolKey(tokenA, tokenB, feeTiers[i])
            );

            if (AddressUtils.isContract(pool) && _isInitialized(pool)) {
                pools[validPools++] = pool;
            }
        }

        _resizeArray(pools, validPools);
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
            revert UniswapV3Adapter__ObservationCardinalityTooLow(
                currentCardinality,
                targetCardinality
            );
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

    function _decimals(address token) internal view returns (uint8) {
        return IERC20Metadata(token).decimals();
    }

    function _isInitialized(address pool) internal view returns (bool) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();
        return sqrtPriceX96 != 0;
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
            revert UniswapV3Adapter__InvalidTimeRange(range[0], range[1]);

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
