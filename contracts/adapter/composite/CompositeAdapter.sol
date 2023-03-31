// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {OracleAdapter} from "../OracleAdapter.sol";

import {CompositeAdapterInternal} from "./CompositeAdapterInternal.sol";

contract CompositeAdapter is CompositeAdapterInternal, OracleAdapter {
    constructor(
        IOracleAdapter chainlinkAdapter,
        IOracleAdapter uniswapAdapter,
        address wrappedNative
    )
        CompositeAdapterInternal(
            chainlinkAdapter,
            uniswapAdapter,
            wrappedNative
        )
    {}

    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool isCached, bool hasPath) {
        _ensureTokenNotWrappedNative(tokenA);
        _ensureTokenNotWrappedNative(tokenB);

        (isCached, hasPath) = UNISWAP_ADAPTER.isPairSupported(
            tokenA,
            WRAPPED_NATIVE
        );

        (bool _isCached, bool _hasPath) = CHAINLINK_ADAPTER.isPairSupported(
            WRAPPED_NATIVE,
            tokenB
        );

        isCached = (!isCached || !_isCached) ? false : true;
        hasPath = (!hasPath || !_hasPath) ? false : true;
    }

    /// @inheritdoc IOracleAdapter
    function upsertPair(address tokenA, address tokenB) external {
        _ensureTokenNotWrappedNative(tokenA);
        _ensureTokenNotWrappedNative(tokenB);

        {
            (bool isCached, bool hasPath) = UNISWAP_ADAPTER.isPairSupported(
                tokenA,
                WRAPPED_NATIVE
            );

            if (!hasPath)
                revert OracleAdapter__PairCannotBeSupported(
                    tokenA,
                    WRAPPED_NATIVE
                );

            if (!isCached && hasPath)
                UNISWAP_ADAPTER.upsertPair(tokenA, WRAPPED_NATIVE);
        }

        {
            (bool isCached, bool hasPath) = CHAINLINK_ADAPTER.isPairSupported(
                WRAPPED_NATIVE,
                tokenB
            );

            if (!hasPath)
                revert OracleAdapter__PairCannotBeSupported(
                    WRAPPED_NATIVE,
                    tokenB
                );

            if (!isCached && hasPath)
                CHAINLINK_ADAPTER.upsertPair(WRAPPED_NATIVE, tokenB);
        }
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18) {
        _ensureTokenNotWrappedNative(tokenIn);
        _ensureTokenNotWrappedNative(tokenOut);
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint32 target
    ) external view returns (UD60x18) {
        _ensureTokenNotWrappedNative(tokenIn);
        _ensureTokenNotWrappedNative(tokenOut);
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target);
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
        (adapterType, path, decimals) = CHAINLINK_ADAPTER.describePricingPath(
            token
        );

        if (path.length == 0)
            (adapterType, path, decimals) = UNISWAP_ADAPTER.describePricingPath(
                token
            );
    }
}
