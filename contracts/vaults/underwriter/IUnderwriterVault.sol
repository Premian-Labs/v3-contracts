// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@solidstate/contracts/token/ERC4626/ISolidStateERC4626.sol";

interface IUnderwriterVault is ISolidStateERC4626 {
    // Errors
    error Vault__InsufficientFunds();
    error Vault__OptionExpired();
    error Vault__OptionPoolNotListed();
    error Vault__OptionPoolNotSupported();
    error Vault__ZeroShares();
    error Vault__AddressZero();
    error Vault__ZeroAsset();
    error Vault__StrikeZero();
    error Vault__MaturityZero();
    error Vault__ZeroPrice();
    error Vault__ZeroVol();
    error Vault__MaturityBounds();
    error Vault__DeltaBounds();
    error Vault__CLevelBounds();
    error Vault__lowCLevel();
    error Vault__NonMonotonicMaturities();
    error Vault__ErroneousNextUnexpiredMaturity();
    error Vault__GreaterThanMaxMaturity();
    error Vault__UtilEstError();
    error Vault__PositionHasNotBeenClosed();

    // Events
    event Sell(
        address indexed buyer,
        uint256 strike,
        uint256 maturity,
        uint256 size,
        uint256 premium,
        uint256 vaultFee
    );

    // @notice Facilitates the purchase of an option for a LT
    // @param taker The LT that is buying the option
    // @param strike The strike price the option
    // @param maturity The maturity of the option
    // @param size The number of contracts
    // @return The premium paid for this option.
    function buy(uint256 strike, uint256 maturity, uint256 size) external;

    function quote(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external view returns (address, uint256, uint256, uint256, uint256);

    // @notice Settle all positions that are past their maturity.
    function settle() external returns (uint256);
}
