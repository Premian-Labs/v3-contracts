// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

interface IERC20Router {
    error ERC20Router__NotAuthorized();

    /// @notice Transfers tokens - caller must be an authorized pool
    /// @param token Address of token to transfer
    /// @param from Address to transfer tokens from
    /// @param to Address to transfer tokens to
    /// @param amount Amount of tokens to transfer
    function safeTransferFrom(address token, address from, address to, uint256 amount) external;
}
