// SPDX-License-Identifier: GPL-2.0-or-later

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

    /// @notice Thrown when trying to add pair where addresses are the same
    error FeedRegistry__TokensAreSame(address tokenA, address tokenB);

    /// @notice Thrown when one of the parameters is a zero address
    error FeedRegistry__ZeroAddress();

    /// @notice Registers mappings of ERC20 token, and denomination (ETH, or USD) to feed
    /// @param args The arguments for the new mappings
    function batchRegisterFeedMappings(FeedMappingArgs[] memory args) external;

    /// @notice Returns the feed for the given pair
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @return The feed address
    function feed(address tokenA, address tokenB) external view returns (address);
}
