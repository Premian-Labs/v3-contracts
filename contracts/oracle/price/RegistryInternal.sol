// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {IRegistryInternal} from "./IRegistryInternal.sol";
import {RegistryStorage} from "./RegistryStorage.sol";
import {Tokens} from "./Tokens.sol";

abstract contract RegistryInternal is IRegistryInternal {
    using RegistryStorage for RegistryStorage.Layout;
    using Tokens for address;

    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable WRAPPED_BTC_TOKEN;

    constructor(address _wrappedNativeToken, address _wrappedBTCToken) {
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        WRAPPED_BTC_TOKEN = _wrappedBTCToken;
    }

    function _exists(address base, address quote) internal view returns (bool) {
        return _feed(base, quote) != address(0);
    }

    function _feed(
        address tokenA,
        address tokenB
    ) internal view returns (address) {
        return
            RegistryStorage.layout().feeds[tokenA.keyForUnsortedPair(tokenB)];
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
