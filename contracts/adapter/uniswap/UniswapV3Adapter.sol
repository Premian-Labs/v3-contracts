// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {PoolAddress} from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {ETH_DECIMALS, Tokens} from "../Tokens.sol";
import {OracleAdapter} from "../OracleAdapter.sol";

import {IUniswapV3Adapter} from "./IUniswapV3Adapter.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

/// @title An implementation of IOracleAdapter that uses Uniswap feeds
/// @notice This oracle adapter will attempt to use all available feeds to determine prices between pairs
contract UniswapV3Adapter is IUniswapV3Adapter, OracleAdapter, OwnableInternal {
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
        uint256 _gasPerCardinality,
        uint256 _gasPerPool
    ) {
        UNISWAP_V3_FACTORY = uniswapV3Factory;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        GAS_PER_CARDINALITY = _gasPerCardinality;
        GAS_TO_SUPPORT_POOL = _gasPerPool;
    }

    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool isCached, bool hasPath) {
        isCached = _poolsForPair(tokenA, tokenB).length > 0;
        hasPath = _getAllPoolsForPair(tokenA, tokenB).length > 0;
    }

    /// @inheritdoc IOracleAdapter
    function upsertPair(address tokenA, address tokenB) external {
        address[] memory pools = _getAllPoolsForPair(tokenA, tokenB);

        if (pools.length == 0)
            revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory poolsToSupport = new address[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            _tryIncreaseCardinality(pool, l.targetCardinality);
            poolsToSupport[i] = pool;
        }

        l.poolsForPair[tokenA.keyForUnsortedPair(tokenB)] = poolsToSupport;
        emit UpdatedPoolsForPair(tokenA, tokenB, poolsToSupport);
    }

    /// @inheritdoc IOracleAdapter
    /// @dev Will revert if the cardinality of an unsupported deployed pool is too low.
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18) {
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    /// @dev Will revert if the cardinality of an unsupported deployed pool is too low.
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (UD60x18) {
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target);
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

        UD60x18 price = ud(
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

    /// @inheritdoc IOracleAdapter
    function describePricingPath(
        address token
    )
        external
        view
        returns (
            AdapterType adapterType,
            address[][] memory path,
            uint8[] memory decimals
        )
    {
        adapterType = AdapterType.UNISWAP_V3;

        path = new address[][](1);
        decimals = new uint8[](2);

        if (token == WRAPPED_NATIVE_TOKEN) {
            address[] memory pool = new address[](1);
            pool[0] = Denominations.ETH;
            path[0] = pool;
            decimals[0] = ETH_DECIMALS;
        } else {
            address[] memory pools = _getAllPoolsForPair(
                token,
                WRAPPED_NATIVE_TOKEN
            );

            if (pools.length > 0) {
                path[0] = pools;

                (address token0, address token1) = token.sortTokens(
                    WRAPPED_NATIVE_TOKEN
                );

                decimals[0] = _decimals(token0);
                decimals[1] = _decimals(token1);
            }
        }

        if (path[0].length == 0) {
            address[][] memory temp = new address[][](0);
            path = temp;
        }

        if (decimals[0] == 0) {
            _resizeArray(decimals, 0);
        } else if (decimals[1] == 0) {
            _resizeArray(decimals, 1);
        }
    }

    /// @inheritdoc IUniswapV3Adapter
    function poolsForPair(
        address tokenA,
        address tokenB
    ) external view returns (address[] memory) {
        return _poolsForPair(tokenA, tokenB);
    }

    /// @inheritdoc IUniswapV3Adapter
    function factory() external view returns (IUniswapV3Factory) {
        return UNISWAP_V3_FACTORY;
    }

    /// @inheritdoc IUniswapV3Adapter
    function period() external view returns (uint32) {
        return UniswapV3AdapterStorage.layout().period;
    }

    /// @inheritdoc IUniswapV3Adapter
    function cardinalityPerMinute() external view returns (uint256) {
        return UniswapV3AdapterStorage.layout().cardinalityPerMinute;
    }

    /// @inheritdoc IUniswapV3Adapter
    function targetCardinality() external view returns (uint16) {
        return UniswapV3AdapterStorage.layout().targetCardinality;
    }

    /// @inheritdoc IUniswapV3Adapter
    function gasPerCardinality() external view returns (uint256) {
        return GAS_PER_CARDINALITY;
    }

    /// @inheritdoc IUniswapV3Adapter
    function gasToSupportPool() external view returns (uint256) {
        return GAS_TO_SUPPORT_POOL;
    }

    /// @inheritdoc IUniswapV3Adapter
    function supportedFeeTiers() external view returns (uint24[] memory) {
        return UniswapV3AdapterStorage.layout().feeTiers;
    }

    /// @inheritdoc IUniswapV3Adapter
    function setPeriod(uint32 newPeriod) external onlyOwner {
        if (newPeriod == 0) revert UniswapV3Adapter__PeriodNotSet();

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        l.period = newPeriod;

        l.targetCardinality =
            uint16((newPeriod * l.cardinalityPerMinute) / 60) +
            1;

        emit UpdatedPeriod(newPeriod);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setCardinalityPerMinute(
        uint256 newCardinalityPerMinute
    ) external onlyOwner {
        if (newCardinalityPerMinute == 0)
            revert UniswapV3Adapter__CardinalityPerMinuteNotSet();

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        l.cardinalityPerMinute = newCardinalityPerMinute;

        l.targetCardinality =
            uint16((l.period * newCardinalityPerMinute) / 60) +
            1;

        emit UpdatedCardinalityPerMinute(newCardinalityPerMinute);
    }

    /// @inheritdoc IUniswapV3Adapter
    function insertFeeTier(uint24 feeTier) external onlyOwner {
        if (UNISWAP_V3_FACTORY.feeAmountTickSpacing(feeTier) == 0)
            revert UniswapV3Adapter__InvalidFeeTier(feeTier);

        uint24[] storage feeTiers = UniswapV3AdapterStorage.layout().feeTiers;
        uint256 feeTiersLength = feeTiers.length;

        for (uint256 i = 0; i < feeTiersLength; i++) {
            if (feeTiers[i] == feeTier)
                revert UniswapV3Adapter__FeeTierExists(feeTier);
        }

        feeTiers.push(feeTier);
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
