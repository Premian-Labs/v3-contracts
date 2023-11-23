// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ISolidStateERC4626} from "@solidstate/contracts/token/ERC4626/ISolidStateERC4626.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";

interface IVault is ISolidStateERC4626 {
    // Errors
    error Vault__AboveMaxSlippage(UD60x18 totalPremium, UD60x18 premiumLimit);
    error Vault__AddressZero();
    error Vault__InsufficientFunds();
    error Vault__InsufficientShorts();
    error Vault__InvalidSettingsUpdate();
    error Vault__InvariantViolated();
    error Vault__MaximumAmountExceeded(UD60x18 maximum, UD60x18 amount);
    error Vault__NotAuthorized();
    error Vault__OptionExpired(uint256 timestamp, uint256 maturity);
    error Vault__OptionPoolNotListed();
    error Vault__OptionTypeMismatchWithVault();
    error Vault__OutOfDeltaBounds();
    error Vault__OutOfDTEBounds();
    error Vault__SellDisabled();
    error Vault__SettingsNotFromRegistry();
    error Vault__SettingsUpdateIsEmpty();
    error Vault__StrikeZero();
    error Vault__TradeMustBeBuy();
    error Vault__TransferExceedsBalance(UD60x18 balance, UD60x18 amount);
    error Vault__ZeroAsset();
    error Vault__ZeroShares();
    error Vault__ZeroSize();

    // Events
    event UpdateQuotes();

    event PricePerShare(UD60x18 pricePerShare);

    event Trade(
        address indexed user,
        address indexed pool,
        UD60x18 contractSize,
        bool isBuy,
        UD60x18 premium,
        UD60x18 takerFee,
        UD60x18 makerRebate,
        UD60x18 vaultFee
    );

    event Settle(address indexed pool, UD60x18 contractSize, UD60x18 fee);

    event ManagementFeePaid(address indexed recipient, uint256 managementFee);

    event PerformanceFeePaid(address indexed recipient, uint256 performanceFee);

    event ClaimProtocolFees(address indexed feeReceiver, uint256 feesClaimed);

    event UpdateSettings(bytes settings);

    /// @notice Updates the vault settings
    /// @param settings Encoding of the new settings
    function updateSettings(bytes memory settings) external;

    /// @notice Return vault abi encoded vault settings
    function getSettings() external view returns (bytes memory);

    /// @notice Returns the trade quote premium
    /// @param poolKey The option pool key
    /// @param size The size of the trade
    /// @param isBuy Whether the trade is a buy or sell
    /// @param taker The address of the taker
    /// @return premium The trade quote premium
    function getQuote(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy,
        address taker
    ) external view returns (uint256 premium);

    /// @notice Executes a trade with the vault
    /// @param poolKey The option pool key
    /// @param size The size of the trade
    /// @param isBuy Whether the trade is a buy or sell
    /// @param premiumLimit The premium limit of the trade
    /// @param referrer The address of the referrer
    function trade(
        IPoolFactory.PoolKey calldata poolKey,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        address referrer
    ) external;

    /// @notice Returns the utilisation rate of the vault
    /// @return The utilisation rate of the vault
    function getUtilisation() external view returns (UD60x18);
}
