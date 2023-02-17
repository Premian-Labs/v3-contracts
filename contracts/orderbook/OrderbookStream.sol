// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract OrderbookStream {
    struct Quote {
        // The pool address of the option quoted
        address pool;
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
        // A category identifier used to be able to invalidate a group of quotes at a lower gas cost compared to invalidating each quote hash individually
        uint256 category;
        // The nonce of the category. This value must match current nonce of the category for the provider, for the quote to be valid
        // When provider wants to invalidate all pending quotes for a category, he can increment this nonce
        uint256 categoryNonce;
        // Timestamp until which the quote is valid
        uint256 deadline;
    }

    event PublishQuote(
        address indexed pool,
        address indexed provider,
        address taker,
        uint256 price,
        uint256 size,
        bool isBuy,
        uint256 category,
        uint256 categoryNonce,
        uint256 deadline
    );

    function add(Quote[] memory quote) external {
        for (uint256 i = 0; i < quote.length; i++) {
            emit PublishQuote(
                quote[i].pool,
                quote[i].provider,
                quote[i].taker,
                quote[i].price,
                quote[i].size,
                quote[i].isBuy,
                quote[i].category,
                quote[i].categoryNonce,
                quote[i].deadline
            );
        }
    }
}
