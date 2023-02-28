// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {ChainlinkAdapterInternal, ChainlinkAdapterStorage} from "./ChainlinkAdapterInternal.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    OracleAdapter,
    SafeOwnable
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;

    constructor(
        address _wrappedNativeToken,
        address _wrappedBTCToken
    ) ChainlinkAdapterInternal(_wrappedNativeToken, _wrappedBTCToken) {}

    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool isCached, bool hasPath) {
        (
            PricingPath path,
            address mappedTokenA,
            address mappedTokenB
        ) = _pathForPair(tokenA, tokenB, true);

        isCached = path != PricingPath.NONE;

        if (isCached) return (isCached, true);

        hasPath =
            _determinePricingPath(mappedTokenA, mappedTokenB) !=
            PricingPath.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function upsertPair(address tokenA, address tokenB) external {
        _upsertPair(tokenA, tokenB);
    }

    /// @inheritdoc IOracleAdapter
    function tryQuote(
        address tokenIn,
        address tokenOut
    ) external returns (uint256) {
        (
            PricingPath path,
            address mappedTokenIn,
            address mappedTokenOut
        ) = _pathForPair(tokenIn, tokenOut, false);

        if (path == PricingPath.NONE) {
            _upsertPair(tokenIn, tokenOut);

            (path, mappedTokenIn, mappedTokenOut) = _pathForPair(
                tokenIn,
                tokenOut,
                false
            );
        }

        return _quote(path, mappedTokenIn, mappedTokenOut);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        (
            PricingPath path,
            address mappedTokenIn,
            address mappedTokenOut
        ) = _pathForPair(tokenIn, tokenOut, false);

        if (path == PricingPath.NONE)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        return _quote(path, mappedTokenIn, mappedTokenOut);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 timestamp
    ) external view returns (uint256) {
        (
            PricingPath path,
            address mappedTokenIn,
            address mappedTokenOut
        ) = _pathForPair(tokenIn, tokenOut, false);

        if (path == PricingPath.NONE)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        return _quote(path, mappedTokenIn, mappedTokenOut);
    }

    /// @inheritdoc IChainlinkAdapter
    function pathForPair(
        address tokenA,
        address tokenB
    ) external view returns (PricingPath) {
        (PricingPath path, , ) = _pathForPair(tokenA, tokenB, false);
        return path;
    }

    /// @inheritdoc IChainlinkAdapter
    function batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) external onlyOwner {
        _batchRegisterFeedMappings(args);
    }

    /// @inheritdoc IChainlinkAdapter
    function feed(
        address tokenA,
        address tokenB
    ) external view returns (address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(
            tokenA,
            tokenB
        );

        return _feed(mappedTokenA, mappedTokenB);
    }
}
