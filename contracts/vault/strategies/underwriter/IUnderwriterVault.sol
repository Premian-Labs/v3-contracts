// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";
import {ISolidStateERC4626} from "@solidstate/contracts/token/ERC4626/ISolidStateERC4626.sol";

import {IVault} from "../../../vault/IVault.sol";

interface IUnderwriterVault is ISolidStateERC4626, IVault {
    // Errors
    error Vault__TradeMustBeBuy();
    error Vault__OptionTypeMismatchWithVault();
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
    error Vault__OutOfTradeBounds();
    error Vault__CLevelBounds();
    error Vault__lowCLevel();
    error Vault__NonMonotonicMaturities();
    error Vault__ErroneousNextUnexpiredMaturity();
    error Vault__GreaterThanMaxMaturity();
    error Vault__UtilEstError();
    error Vault__PositionHasNotBeenClosed();

    // Structs
    // The structs below are used as a way to reduce stack depth and avoid "stack too deep" errors
    struct UnexpiredListingVars {
        // A list of strikes for a set of listings
        UD60x18[] strikes;
        // A list of time until maturity (years) for a set of listings
        UD60x18[] timeToMaturities;
        // A list of maturities for a set of listings
        uint256[] maturities;
    }

    struct LockedSpreadVars {
        UD60x18 totalLockedSpread;
        UD60x18 spreadUnlockingRate;
        uint256 lastSpreadUnlockUpdate;
    }

    struct QuoteVars {
        // timestamp of the quote/trade
        uint256 timestamp;
        // spot price
        UD60x18 spot;
        // strike price of the listing
        UD60x18 strike;
        // maturity of the listing
        uint256 maturity;
        // pool address of the listing
        address poolAddr;
        // time until maturity (years)
        UD60x18 tau;
        // implied volatility of the listing
        UD60x18 sigma;
        // risk-free rate
        UD60x18 riskFreeRate;
        // option delta
        SD59x18 delta;
        // option price
        UD60x18 price;
        // size of quote/trade
        UD60x18 size;
        // premium associated to the BSM price of the option
        UD60x18 premium;
        // C-level post-trade
        UD60x18 cLevel;
        // spread added on to premium due to C-level
        UD60x18 spread;
        // fee for minting the option through the pool
        UD60x18 mintingFee;
    }

    // Events
    event Sell(
        address indexed buyer,
        uint256 strike,
        uint256 maturity,
        uint256 size,
        uint256 premium,
        uint256 vaultFee
    );

    /// @notice Settle all positions that are past their maturity.
    function settle() external returns (uint256);
}
