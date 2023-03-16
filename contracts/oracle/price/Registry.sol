// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {IRegistry} from "./IRegistry.sol";
import {RegistryInternal} from "./RegistryInternal.sol";
import {RegistryStorage} from "./RegistryStorage.sol";
import {Tokens} from "./Tokens.sol";

/// @title Adapter registry implementation
contract Registry is IRegistry, RegistryInternal, SafeOwnable {
    using RegistryStorage for RegistryStorage.Layout;
    using Tokens for address;

    constructor(
        address _wrappedNativeToken,
        address _wrappedBTCToken
    ) RegistryInternal(_wrappedNativeToken, _wrappedBTCToken) {}

    /// @inheritdoc IRegistry
    function batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) external onlyOwner {
        for (uint256 i = 0; i < args.length; i++) {
            address token = _tokenToDenomination(args[i].token);
            address denomination = args[i].denomination;

            if (token == denomination)
                revert Registry__TokensAreSame(token, denomination);

            if (token == address(0) || denomination == address(0))
                revert Registry__ZeroAddress();

            bytes32 keyForPair = token.keyForUnsortedPair(denomination);
            RegistryStorage.layout().feeds[keyForPair] = args[i].feed;
        }

        emit FeedMappingsRegistered(args);
    }

    /// @inheritdoc IRegistry
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
