// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {OracleAdapterInternal} from "../OracleAdapterInternal.sol";

import {ICompositeAdapterInternal} from "./ICompositeAdapterInternal.sol";

contract CompositeAdapterInternal is
    ICompositeAdapterInternal,
    OracleAdapterInternal
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

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint32 target
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

    function _ensureTokenNotWrappedNative(address token) internal view {
        if (token == WRAPPED_NATIVE)
            revert CompositeAdapter__TokenCannotBeWrappedNative();
    }
}
