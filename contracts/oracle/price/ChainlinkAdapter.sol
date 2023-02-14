// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";

import {ChainlinkAdapterInternal, ChainlinkAdapterStorage} from "./ChainlinkAdapterInternal.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    ERC165Base,
    SafeOwnable
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;

    constructor(
        FeedMappingArgs[] memory feedMappingArgs,
        DenominationMappingArgs[] memory denominationMappingArgs
    ) {
        _batchRegisterDenominationMappings(denominationMappingArgs);
        _batchRegisterFeedMappings(feedMappingArgs);

        _setOwner(msg.sender);
        _setSupportsInterface(type(IChainlinkAdapter).interfaceId, true);
    }

    /// @inheritdoc IOracleAdapter
    function canSupportPair(
        address tokenA,
        address tokenB
    ) external view returns (bool) {
        (address _tokenA, address _tokenB) = _mapToDenominationAndSort(
            tokenA,
            tokenB
        );

        PricingPath path = _determinePricingPath(_tokenA, _tokenB);
        return path != PricingPath.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) external view override(IOracleAdapter, OracleAdapter) returns (bool) {
        return _isPairAlreadySupported(tokenA, tokenB);
    }

    // /// @inheritdoc IChainlinkAdapter
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
            revert OracleAdapter__PairNotSupportedYet(tokenIn, tokenOut);

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
    function batchRegisterDenominationMappings(
        DenominationMappingArgs[] memory args
    ) external onlyOwner {
        _batchRegisterDenominationMappings(args);
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

    /// @inheritdoc IChainlinkAdapter
    function denomination(address token) external view returns (address) {
        return _denomination(token);
    }

    /// @inheritdoc IChainlinkAdapter
    function maxDelay() external pure returns (uint32) {
        return MAX_DELAY;
    }
}
