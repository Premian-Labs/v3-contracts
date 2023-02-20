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
    )
        external
        view
        override(IOracleAdapter)
        returns (bool isCached, bool hasPath)
    {
        (
            address mappedTokenA,
            address mappedTokenB
        ) = _mapToDenominationAndSort(tokenA, tokenB);

        PricingPath path = ChainlinkAdapterStorage.layout().pathForPair[
            _keyForSortedPair(mappedTokenA, mappedTokenB)
        ];

        isCached = path != PricingPath.NONE;

        if (isCached) return (isCached, true);

        hasPath =
            _determinePricingPath(mappedTokenA, mappedTokenB) !=
            PricingPath.NONE;
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
        ) = _pathForPairAndUnsortedMappedTokens(tokenIn, tokenOut);

        if (path == PricingPath.NONE) {
            _addOrModifySupportForPair(tokenIn, tokenOut);

            (
                path,
                mappedTokenIn,
                mappedTokenOut
            ) = _pathForPairAndUnsortedMappedTokens(tokenIn, tokenOut);
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
        ) = _pathForPairAndUnsortedMappedTokens(tokenIn, tokenOut);

        if (path == PricingPath.NONE)
            revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);

        return _quote(path, mappedTokenIn, mappedTokenOut);
    }

    /// @inheritdoc IChainlinkAdapter
    function pathForPair(
        address tokenA,
        address tokenB
    ) external view returns (PricingPath) {
        return _pathForPair(tokenA, tokenB);
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
        (address mappedTokenA, address mappedTokenB) = _mapPairToDenomination(
            tokenA,
            tokenB
        );

        return _feed(mappedTokenA, mappedTokenB);
    }
}
