// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {IFeedRegistry} from "./IFeedRegistry.sol";
import {FeedRegistryStorage} from "./FeedRegistryStorage.sol";
import {Tokens} from "./Tokens.sol";

/// @title Adapter feed registry implementation
abstract contract FeedRegistry is IFeedRegistry {
    using FeedRegistryStorage for FeedRegistryStorage.Layout;
    using Tokens for address;

    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable WRAPPED_BTC_TOKEN;

    constructor(address _wrappedNativeToken, address _wrappedBTCToken) {
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        WRAPPED_BTC_TOKEN = _wrappedBTCToken;
    }

    /// @inheritdoc IFeedRegistry
    function batchRegisterFeedMappings(FeedMappingArgs[] memory args) external virtual;

    /// @inheritdoc IFeedRegistry
    function feed(address tokenA, address tokenB) external view returns (address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(tokenA, tokenB);
        return _feed(mappedTokenA, mappedTokenB);
    }

    /// @notice Returns the feed for `tokenA` and `tokenB`
    function _feed(address tokenA, address tokenB) internal view returns (address) {
        return FeedRegistryStorage.layout().feeds[tokenA.keyForUnsortedPair(tokenB)];
    }

    /// @notice Returns true if a feed exists for `tokenA` and `tokenB`
    function _feedExists(address tokenA, address tokenB) internal view returns (bool) {
        return _feed(tokenA, tokenB) != address(0);
    }

    /// @notice Returns the denomination mapped to `token`, if it has one
    /// @dev Should only map wrapped tokens which are guaranteed to have a 1:1 ratio
    function _tokenToDenomination(address token) internal view returns (address) {
        return token == WRAPPED_NATIVE_TOKEN ? Denominations.ETH : token;
    }

    /// @notice Returns the sorted and mapped tokens for `tokenA` and `tokenB`
    function _mapToDenominationAndSort(address tokenA, address tokenB) internal view returns (address, address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(tokenA, tokenB);
        return mappedTokenA.sortTokens(mappedTokenB);
    }

    /// @notice Returns the mapped token denominations for `tokenA` and `tokenB`
    function _mapToDenomination(
        address tokenA,
        address tokenB
    ) internal view returns (address mappedTokenA, address mappedTokenB) {
        mappedTokenA = _tokenToDenomination(tokenA);
        mappedTokenB = _tokenToDenomination(tokenB);
    }
}
