// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ChainlinkAdapterInternal} from "./ChainlinkAdapterInternal.sol";
import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";
import {OracleAdapter} from "./OracleAdapter.sol";
import {Tokens} from "./Tokens.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    OracleAdapter
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;
    using Tokens for address;

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
        (
            address mappedTokenA,
            address mappedTokenB
        ) = _mapToDenominationAndSort(tokenA, tokenB);

        PricingPath path = _determinePricingPath(mappedTokenA, mappedTokenB);
        bytes32 keyForPair = mappedTokenA.keyForSortedPair(mappedTokenB);

        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage
            .layout();

        if (path == PricingPath.NONE) {
            // Check if there is a current path. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current path and continue working as expected.
            // If there was no supported path, and there still isn't, then we will fail
            PricingPath _currentPath = l.pathForPair[keyForPair];

            if (_currentPath == PricingPath.NONE) {
                revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);
            }
        }

        if (l.pathForPair[keyForPair] == path) return;

        l.pathForPair[keyForPair] = path;
        emit UpdatedPathForPair(mappedTokenA, mappedTokenB, path);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (uint256) {
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target);
    }

    /// @inheritdoc IChainlinkAdapter
    function pathForPair(
        address tokenA,
        address tokenB
    ) external view returns (PricingPath) {
        (PricingPath path, , ) = _pathForPair(tokenA, tokenB, false);
        return path;
    }
}
