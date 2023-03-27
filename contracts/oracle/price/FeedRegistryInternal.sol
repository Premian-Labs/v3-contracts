// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {FeedRegistryStorage} from "./FeedRegistryStorage.sol";
import {Tokens} from "./Tokens.sol";

abstract contract FeedRegistryInternal {
    using FeedRegistryStorage for FeedRegistryStorage.Layout;
    using Tokens for address;

    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable WRAPPED_BTC_TOKEN;

    constructor(address _wrappedNativeToken, address _wrappedBTCToken) {
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        WRAPPED_BTC_TOKEN = _wrappedBTCToken;
    }

    function _feedExists(
        address base,
        address quote
    ) internal view returns (bool) {
        return _feed(base, quote) != address(0);
    }

    function _feed(
        address tokenA,
        address tokenB
    ) internal view returns (address) {
        return
            FeedRegistryStorage.layout().feeds[
                tokenA.keyForUnsortedPair(tokenB)
            ];
    }

    /// @dev Should only map wrapped tokens which are guaranteed to have a 1:1 ratio
    function _tokenToDenomination(
        address token
    ) internal view returns (address) {
        return token == WRAPPED_NATIVE_TOKEN ? Denominations.ETH : token;
    }

    function _mapToDenominationAndSort(
        address tokenA,
        address tokenB
    ) internal view returns (address, address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(
            tokenA,
            tokenB
        );

        return mappedTokenA.sortTokens(mappedTokenB);
    }

    function _mapToDenomination(
        address tokenA,
        address tokenB
    ) internal view returns (address mappedTokenA, address mappedTokenB) {
        mappedTokenA = _tokenToDenomination(tokenA);
        mappedTokenB = _tokenToDenomination(tokenB);
    }
}
