// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {IFeedRegistry} from "./IFeedRegistry.sol";
import {FeedRegistryInternal} from "./FeedRegistryInternal.sol";
import {FeedRegistryStorage} from "./FeedRegistryStorage.sol";
import {Tokens} from "./Tokens.sol";

/// @title Adapter feed registry implementation
contract FeedRegistry is IFeedRegistry, FeedRegistryInternal, SafeOwnable {
    using FeedRegistryStorage for FeedRegistryStorage.Layout;
    using Tokens for address;

    constructor(
        address _wrappedNativeToken,
        address _wrappedBTCToken
    ) FeedRegistryInternal(_wrappedNativeToken, _wrappedBTCToken) {}

    /// @inheritdoc IFeedRegistry
    function batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) external onlyOwner {
        for (uint256 i = 0; i < args.length; i++) {
            address token = _tokenToDenomination(args[i].token);
            address denomination = args[i].denomination;

            if (token == denomination)
                revert FeedRegistry__TokensAreSame(token, denomination);

            if (token == address(0) || denomination == address(0))
                revert FeedRegistry__ZeroAddress();

            bytes32 keyForPair = token.keyForUnsortedPair(denomination);
            FeedRegistryStorage.layout().feeds[keyForPair] = args[i].feed;
        }

        emit FeedMappingsRegistered(args);
    }

    /// @inheritdoc IFeedRegistry
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
