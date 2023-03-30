// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";
import {ISolidStateERC4626} from "@solidstate/contracts/token/ERC4626/ISolidStateERC4626.sol";

import {IVault} from "../../../vault/IVault.sol";

interface IUnderwriterVault is ISolidStateERC4626, IVault {
    // Errors
    error Vault__TradeMustBeBuy();
    error Vault__ZeroSize();
    error Vault__OptionTypeMismatchWithVault();
    error Vault__InsufficientFunds();
    error Vault__OptionExpired();
    error Vault__OptionPoolNotListed();
    error Vault__ZeroShares();
    error Vault__AddressZero();
    error Vault__ZeroAsset();
    error Vault__StrikeZero();
    error Vault__OutOfTradeBounds(string valueName);
    error Vault__UtilisationOutOfBounds();

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
        // premium associated to the BSM price of the option (price * size)
        UD60x18 premium;
        // C-level post-trade
        UD60x18 cLevel;
        // spread added on to premium due to C-level
        UD60x18 spread;
        // fee for minting the option through the pool
        UD60x18 mintingFee;
    }

    struct FeeVars {
        UD60x18 pps;
        UD60x18 ppsAvg;
        UD60x18 shares;
        UD60x18 assets;
        UD60x18 balanceShares;
        UD60x18 performance;
        UD60x18 performanceFeeInShares;
        UD60x18 performanceFeeInAssets;
        UD60x18 managementFeeInShares;
        UD60x18 managementFeeInAssets;
        UD60x18 totalFeeInShares;
        UD60x18 totalFeeInAssets;
    }

    // Events
    event ClaimProtocolFees(address indexed feeReceiver, UD60x18 feesClaimed);

    /// @notice Settle all positions that are past their maturity.
    function settle() external;
}
