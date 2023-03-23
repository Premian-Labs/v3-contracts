// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IUniswapV3Factory} from "../../vendor/uniswap/IUniswapV3Factory.sol";

import {IUniswapV3Adapter} from "./IUniswapV3Adapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";
import {UniswapV3AdapterInternal} from "./UniswapV3AdapterInternal.sol";
import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles and
///         https://github.com/Mean-Finance/uniswap-v3-oracle
contract UniswapV3Adapter is
    IUniswapV3Adapter,
    OracleAdapter,
    SafeOwnable,
    UniswapV3AdapterInternal
{
    using SafeCast for uint256;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        uint256 _gasPerCardinality,
        uint256 _gasPerPool
    )
        UniswapV3AdapterInternal(
            uniswapV3Factory,
            _gasPerCardinality,
            _gasPerPool
        )
    {}

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
        uint256 poolsLength = pools.length;

        if (poolsLength == 0)
            revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory poolsToSupport = new address[](poolsLength);

        for (uint256 i; i < poolsLength; i++) {
            address pool = pools[i];
            _tryIncreaseCardinality(pool, l.targetCardinality);
            poolsToSupport[i] = pool;
        }

        l.poolsForPair[_keyForUnsortedPair(tokenA, tokenB)] = poolsToSupport;
        emit UpdatedPoolsForPair(tokenA, tokenB, poolsToSupport);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18) {
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (UD60x18) {
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target.toUint32());
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
        // ToDo : Implement
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
    function cardinalityPerMinute() external view returns (uint8) {
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
        uint8 newCardinalityPerMinute
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

        for (uint256 i; i < feeTiersLength; i++) {
            if (feeTiers[i] == feeTier)
                revert UniswapV3Adapter__FeeTierExists(feeTier);
        }

        feeTiers.push(feeTier);
    }
}
