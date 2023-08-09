// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IFeeConverter {
    error FeeConverter__NotAuthorized();

    event Converted(
        address indexed account,
        address indexed token,
        uint256 inAmount,
        uint256 outAmount,
        uint256 treasuryAmount
    );

    event SetAuthorized(address indexed account, bool isAuthorized);

    /// @notice get the exchange helper address
    /// @return exchangeHelper exchange helper address
    function getExchangeHelper() external view returns (address exchangeHelper);

    /// @notice convert held tokens to USDC and distribute as rewards
    /// @param sourceToken address of token to convert
    /// @param callee exchange address to call to execute the trade.
    /// @param allowanceTarget address for which to set allowance for the trade
    /// @param data calldata to execute the trade
    function convert(address sourceToken, address callee, address allowanceTarget, bytes calldata data) external;

    /// @notice Redeem shares from an ERC4626 vault
    /// @param vault address of the ERC4626 vault to redeem from
    /// @param shareAmount quantity of shares to redeem
    /// @return assetAmount quantity of assets received
    function redeem(address vault, uint256 shareAmount) external returns (uint256 assetAmount);
}
