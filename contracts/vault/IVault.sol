// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC4626Internal} from "@solidstate/contracts/interfaces/IERC4626Internal.sol";
import {IERC20Internal} from "@solidstate/contracts/interfaces/IERC20Internal.sol";

import {IPoolFactory} from "../factory/IPoolFactory.sol";

interface IVault is IERC4626Internal, IERC20Internal {
    // Errors
    error Vault__AboveMaxSlippage(UD60x18 totalPremium, UD60x18 premiumLimit);
    error Vault__AddressZero();
    error Vault__InsufficientFunds();
    error Vault__MaximumAmountExceeded(UD60x18 maximum, UD60x18 amount);
    error Vault__OptionExpired(uint256 timestamp, uint256 maturity);
    error Vault__OptionPoolNotListed();
    error Vault__OptionTypeMismatchWithVault();
    error Vault__OutOfDeltaBounds();
    error Vault__OutOfDTEBounds();
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

    event Swap(
        address indexed sender,
        address recipient,
        address indexed tokenIn,
        address indexed tokenOut,
        UD60x18 amountIn,
        UD60x18 amountOut,
        UD60x18 takerFee,
        UD60x18 makerRebate,
        UD60x18 vaultFee
    );

    event Borrow(
        bytes32 indexed borrowId,
        address indexed from,
        address indexed borrowToken,
        address collateralToken,
        UD60x18 sizeBorrowed,
        UD60x18 collateralLocked,
        UD60x18 borrowFee
    );

    event BorrowLiquidated(
        bytes32 indexed borrowId,
        address indexed from,
        address indexed collateralToken,
        UD60x18 collateralLiquidated
    );

    event RepayBorrow(
        bytes32 indexed borrowId,
        address indexed from,
        address indexed borrowToken,
        address collateralToken,
        UD60x18 amountRepaid,
        UD60x18 collateralUnlocked,
        UD60x18 repayFee
    );

    event ManagementFeePaid(address indexed recipient, uint256 managementFee);

    event PerformanceFeePaid(address indexed recipient, uint256 performanceFee);

    event ClaimProtocolFees(address indexed feeReceiver, uint256 feesClaimed);

    /// @notice Updates the vault settings
    /// @param settings Encoding of the new settings
    function updateSettings(bytes memory settings) external;

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
}
