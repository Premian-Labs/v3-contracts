// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

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
        IPoolFactory.PoolKey indexed poolKey,
        address indexed provider,
        address taker,
        uint256 price,
        uint256 size,
        bool isBuy,
        uint256 deadline,
        uint256 salt,
        Signature signature
    );

    function add(Quote[] memory quote) external {
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
                quote[i].signature
            );
        }
    }
}
