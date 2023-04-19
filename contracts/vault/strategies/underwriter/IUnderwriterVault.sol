// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {ISolidStateERC4626} from "@solidstate/contracts/token/ERC4626/ISolidStateERC4626.sol";

import {IVault} from "../../../vault/IVault.sol";

interface IUnderwriterVault is ISolidStateERC4626, IVault {
    // Errors
    error Vault__UtilisationOutOfBounds();

    // Structs
    struct UnderwriterVaultSettings {
        // The curvature parameter
        UD60x18 alpha;
        // The decay rate of the C-level back down to ordinary level
        UD60x18 hourlyDecayDiscount;
        // The minimum C-level allowed by the C-level mechanism
        UD60x18 minCLevel;
        // The maximum C-level allowed by the C-level mechanism
        UD60x18 maxCLevel;
        // The maximum time until maturity the vault will underwrite
        UD60x18 maxDTE;
        // The minimum time until maturity the vault will underwrite
        UD60x18 minDTE;
        // The maximum delta the vault will underwrite
        UD60x18 minDelta;
        // The minimum delta the vault will underwrite
        UD60x18 maxDelta;
    }

    // The structs below are used as a way to reduce stack depth and avoid "stack too deep" errors
    struct UnexpiredListingVars {
        UD60x18 spot;
        UD60x18 riskFreeRate;
        // A list of strikes for a set of listings
        UD60x18[] strikes;
        // A list of time until maturity (years) for a set of listings
        UD60x18[] timeToMaturities;
        // A list of maturities for a set of listings
        uint256[] maturities;
        UD60x18[] sigmas;
    }

    struct LockedSpreadInternal {
        UD60x18 totalLockedSpread;
        UD60x18 spreadUnlockingRate;
        uint256 lastSpreadUnlockUpdate;
    }

    struct QuoteVars {
        // spot price
        UD60x18 spot;
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
        // C-level post-trade
        UD60x18 cLevel;
    }

    struct QuoteInternal {
        // strike price of the listing
        address pool;
        // premium associated to the BSM price of the option (price * size)
        UD60x18 premium;
        // spread added on to premium due to C-level
        UD60x18 spread;
        // fee for minting the option through the pool
        UD60x18 mintingFee;
    }

    struct FeeInternal {
        // amount of assets that the user's shares are worth currently
        UD60x18 assets;
        // total amount of shares the user owns
        UD60x18 balanceShares;
        // performance of the user's deposited capital (1.2 meaning 20% in returns, 0.9 meaning -10% in returns)
        UD60x18 performance;
        // performance fee given to the vault based on the amount transferred denoted in assets
        UD60x18 performanceFeeInAssets;
        // management fee given to the vault based on the amount transferred denoted in assets
        UD60x18 managementFeeInAssets;
        // total fee given to the vault based on the amount transferred denoted in shares
        UD60x18 totalFeeInShares;
        // total fee given to the vault based on the amount transferred denoted in the assets
        UD60x18 totalFeeInAssets;
    }

    // Events
    event ClaimProtocolFees(address indexed feeReceiver, UD60x18 feesClaimed);

    /// @notice Settles all expired option positions.
    function settle() external;
}
