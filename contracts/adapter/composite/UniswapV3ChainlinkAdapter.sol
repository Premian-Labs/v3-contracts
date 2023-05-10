// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {OracleAdapter} from "../OracleAdapter.sol";

import {IUniswapV3ChainlinkAdapter} from "./IUniswapV3ChainlinkAdapter.sol";

/// @title An implementation of IOracleAdapter that combines the UniswapV3 and Chainlink adapter feeds
/// @notice This oracle adapter will fetch the price for tokenIn/ETH from UniswapV3 adapter, then
///         convert to tokenIn/tokenOut using ETH/tokenOut from the Chainlink adapter.
///         i.e. tokenIn/ETH * ETH/tokenOut -> tokenIn/tokenOut
contract UniswapV3ChainlinkAdapter is
    IUniswapV3ChainlinkAdapter,
    OracleAdapter
{
    IOracleAdapter internal immutable CHAINLINK_ADAPTER;
    IOracleAdapter internal immutable UNISWAP_ADAPTER;
    address internal immutable WRAPPED_NATIVE;

    constructor(
        IOracleAdapter chainlinkAdapter,
        IOracleAdapter uniswapAdapter,
        address wrappedNative
    ) {
        CHAINLINK_ADAPTER = chainlinkAdapter;
        UNISWAP_ADAPTER = uniswapAdapter;
        WRAPPED_NATIVE = wrappedNative;
    }

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
        uint256 target
    ) external view returns (UD60x18) {
        _ensureTokenNotWrappedNative(tokenIn);
        _ensureTokenNotWrappedNative(tokenOut);
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target);
    }

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        {
            (, bool hasPath) = UNISWAP_ADAPTER.isPairSupported(
                tokenIn,
                WRAPPED_NATIVE
            );

            if (!hasPath)
                revert OracleAdapter__PairCannotBeSupported(
                    tokenIn,
                    WRAPPED_NATIVE
                );
        }

        {
            (, bool hasPath) = CHAINLINK_ADAPTER.isPairSupported(
                WRAPPED_NATIVE,
                tokenOut
            );

            if (!hasPath)
                revert OracleAdapter__PairCannotBeSupported(
                    WRAPPED_NATIVE,
                    tokenOut
                );
        }

        if (target == 0) {
            return
                UNISWAP_ADAPTER.quote(tokenIn, WRAPPED_NATIVE) *
                CHAINLINK_ADAPTER.quote(WRAPPED_NATIVE, tokenOut);
        } else {
            return
                UNISWAP_ADAPTER.quoteFrom(tokenIn, WRAPPED_NATIVE, target) *
                CHAINLINK_ADAPTER.quoteFrom(WRAPPED_NATIVE, tokenOut, target);
        }
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

    function _ensureTokenNotWrappedNative(address token) internal view {
        if (token == WRAPPED_NATIVE)
            revert UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative();
    }
}
