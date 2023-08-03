// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IFeedRegistry {
    struct FeedMappingArgs {
        address token;
        address denomination;
        address feed;
    }

    /// @notice Emitted when new price feed mappings are registered
    /// @param args The arguments for the new mappings
    event FeedMappingsRegistered(FeedMappingArgs[] args);

    /// @notice Registers mappings of ERC20 token, and denomination (ETH, BTC, or USD) to feed
    /// @param args The arguments for the new mappings
    function batchRegisterFeedMappings(FeedMappingArgs[] memory args) external;

    /// @notice Returns the feed for `token` and `denomination`
    /// @param token The exchange token (ERC20 token)
    /// @param denomination The Chainlink token denomination to quote against (ETH, BTC, or USD)
    /// @return The feed address
    function feed(address token, address denomination) external view returns (address);
}
