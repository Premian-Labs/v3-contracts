// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {ETH_DECIMALS, Tokens} from "../Tokens.sol";
import {OracleAdapter} from "../OracleAdapter.sol";

import {IUniswapV3Adapter} from "./IUniswapV3Adapter.sol";
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
    using Tokens for address;
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    constructor(
        IUniswapV3Factory uniswapV3Factory,
        address wrappedNativeToken,
        uint256 _gasPerCardinality,
        uint256 _gasPerPool
    )
        UniswapV3AdapterInternal(
            uniswapV3Factory,
            wrappedNativeToken,
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

        if (pools.length == 0)
            revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);

        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        address[] memory poolsToSupport = new address[](pools.length);

        for (uint256 i; i < pools.length; i++) {
            address pool = pools[i];
            _tryIncreaseCardinality(pool, l.targetCardinality);
            poolsToSupport[i] = pool;
        }

        l.poolsForPair[tokenA.keyForUnsortedPair(tokenB)] = poolsToSupport;
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
