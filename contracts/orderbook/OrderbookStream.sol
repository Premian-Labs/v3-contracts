// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IPoolFactory} from "contracts/factory/IPoolFactory.sol";

contract OrderbookStream {
    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct Quote {
        // The pool key
        IPoolFactory.PoolKey poolKey;
        // The provider of the quote
        address provider;
        // The taker of the quote (address(0) if quote should be usable by anyone)
        address taker;
        // The normalized option price
        uint256 price;
        // The max size
        uint256 size;
        // Whether provider is buying or selling
        bool isBuy;
        // Timestamp until which the quote is valid
        uint256 deadline;
        // Salt to make quote unique
        uint256 salt;
        // Signature of the quote
        Signature signature;
    }

    event PublishQuote(
        // When a struct is used as indexed param, it is stored as a Keccak-256 hash of the abi encoding of that struct
        // https://docs.soliditylang.org/en/v0.8.19/abi-spec.html#indexed-event-encoding
        IPoolFactory.PoolKey indexed poolKeyHash,
        address indexed provider,
        address taker,
        uint256 price,
        uint256 size,
        bool isBuy,
        uint256 deadline,
        uint256 salt,
        Signature signature,
        // We still emit the poolKey as non indexed param to be able to access the elements of the poolKey in the event
        // This is why the same variable is emitted twice
        IPoolFactory.PoolKey poolKey
    );

    /// @notice Emits PublishQuote event for `quote`
    function add(Quote[] calldata quote) external {
        for (uint256 i = 0; i < quote.length; i++) {
            emit PublishQuote(
                quote[i].poolKey,
                quote[i].provider,
                quote[i].taker,
                quote[i].price,
                quote[i].size,
                quote[i].isBuy,
                quote[i].deadline,
                quote[i].salt,
                quote[i].signature,
                quote[i].poolKey
            );
        }
    }
}
