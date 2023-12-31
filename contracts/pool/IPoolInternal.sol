// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {IPosition} from "../libraries/IPosition.sol";
import {IPricing} from "../libraries/IPricing.sol";
import {UD50x28} from "../libraries/UD50x28.sol";
import {SD49x28} from "../libraries/SD49x28.sol";

import {IUserSettings} from "../settings/IUserSettings.sol";

interface IPoolInternal is IPosition, IPricing {
    error Pool__AboveQuoteSize(UD60x18 size, UD60x18 quoteSize);
    error Pool__AboveMaxSlippage(uint256 value, uint256 minimum, uint256 maximum);
    error Pool__ActionNotAuthorized(address user, address sender, IUserSettings.Action action);
    error Pool__CostExceedsPayout(UD60x18 cost, UD60x18 payout);
    error Pool__CostNotAuthorized(UD60x18 costInWrappedNative, UD60x18 authorizedCostInWrappedNative);
    error Pool__DifferenceOfSizeAndContractDeltaTooLarge(UD60x18 diff, UD60x18 size);
    error Pool__FlashLoanCallbackFailed();
    error Pool__FlashLoanNotRepayed();
    error Pool__InsufficientAskLiquidity();
    error Pool__InsufficientBidLiquidity();
    error Pool__InsufficientFunds();
    error Pool__InsufficientLiquidity();
    error Pool__InvalidAssetUpdate(SD59x18 deltaLongs, SD59x18 deltaShorts);
    error Pool__InvalidBelowPrice(UD60x18 price, UD60x18 priceBelow);
    error Pool__InvalidMonth(uint256 month);
    error Pool__InvalidPositionState(uint256 balance, uint256 lastDeposit);
    error Pool__InvalidQuoteOBSignature();
    error Pool__InvalidQuoteOBTaker();
    error Pool__InvalidRange(UD60x18 lower, UD60x18 upper);
    error Pool__InvalidReconciliation(uint256 crossings);
    error Pool__InvalidSize(UD60x18 lower, UD60x18 upper, UD60x18 depositSize);
    error Pool__InvalidTickPrice();
    error Pool__InvalidTickUpdate();
    error Pool__InvalidTransfer();
    error Pool__NotEnoughTokens(UD60x18 balance, UD60x18 size);
    error Pool__NotPoolToken(address token);
    error Pool__NotWrappedNativeTokenPool();
    error Pool__OperatorNotAuthorized(address sender);
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__OutOfBoundsPrice(UD60x18 price);
    error Pool__PositionDoesNotExist(address owner, uint256 tokenId);
    error Pool__PositionCantHoldLongAndShort(UD60x18 longs, UD60x18 shorts);
    error Pool__QuoteOBCancelled();
    error Pool__QuoteOBExpired();
    error Pool__QuoteOBOverfilled(UD60x18 filledAmount, UD60x18 size, UD60x18 quoteOBSize);
    error Pool__SettlementFailed();
    error Pool__SettlementPriceAlreadyCached();
    error Pool__TickDeltaNotZero(SD59x18 tickDelta);
    error Pool__TickNotFound(UD60x18 price);
    error Pool__TickOutOfRange(UD60x18 price);
    error Pool__TickWidthInvalid(UD60x18 price);
    error Pool__WithdrawalDelayNotElapsed(uint256 unlockTime);
    error Pool__ZeroSize();

    struct Tick {
        SD49x28 delta;
        UD50x28 externalFeeRate;
        SD49x28 longDelta;
        SD49x28 shortDelta;
        uint256 counter;
    }

    struct TickWithRates {
        Tick tick;
        UD60x18 price;
        UD50x28 longRate;
        UD50x28 shortRate;
    }

    struct QuoteOB {
        // The provider of the OB quote
        address provider;
        // The taker of the OB quote (address(0) if OB quote should be usable by anyone)
        address taker;
        // The normalized option price (18 decimals)
        UD60x18 price;
        // The max size (18 decimals)
        UD60x18 size;
        // Whether provider is buying or selling
        bool isBuy;
        // Timestamp until which the OB quote is valid
        uint256 deadline;
        // Salt to make OB quote unique
        uint256 salt;
    }

    enum InvalidQuoteOBError {
        None,
        QuoteOBExpired,
        QuoteOBCancelled,
        QuoteOBOverfilled,
        OutOfBoundsPrice,
        InvalidQuoteOBTaker,
        InvalidQuoteOBSignature,
        InvalidAssetUpdate,
        InsufficientCollateralAllowance,
        InsufficientCollateralBalance,
        InsufficientLongBalance,
        InsufficientShortBalance
    }

    ////////////////////
    ////////////////////
    // The structs below are used as a way to reduce stack depth and avoid "stack too deep" errors

    struct TradeArgsInternal {
        // The account doing the trade
        address user;
        // The referrer of the user doing the trade
        address referrer;
        // The number of contracts being traded (18 decimals)
        UD60x18 size;
        // Whether the taker is buying or selling
        bool isBuy;
        // Tx will revert if total premium is above this value when buying, or below this value when selling.
        // (poolToken decimals)
        uint256 premiumLimit;
    }

    struct ReferralVarsInternal {
        UD60x18 totalRebate;
        UD60x18 primaryRebate;
        UD60x18 secondaryRebate;
    }

    struct TradeVarsInternal {
        UD60x18 maxSize;
        UD60x18 tradeSize;
        UD50x28 oldMarketPrice;
        UD60x18 totalPremium;
        UD60x18 totalTakerFees;
        UD60x18 totalProtocolFees;
        UD50x28 longDelta;
        UD50x28 shortDelta;
        ReferralVarsInternal referral;
        UD60x18 totalMintBurn;
        UD60x18 offset;
        UD60x18 premiumWithFees;
    }

    struct DepositArgsInternal {
        // The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and
        // validated on-chain to save gas (18 decimals)
        UD60x18 belowLower;
        // The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and
        // validated on-chain to save gas (18 decimals)
        UD60x18 belowUpper;
        // The position size to deposit (18 decimals)
        UD60x18 size;
        // minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
        UD60x18 minMarketPrice;
        // maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
        UD60x18 maxMarketPrice;
    }

    struct WithdrawVarsInternal {
        bytes32 pKeyHash;
        uint256 tokenId;
        UD60x18 initialSize;
        UD50x28 liquidityPerTick;
        bool isFullWithdrawal;
        SD49x28 tickDelta;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct FillQuoteOBArgsInternal {
        // The user filling the OB quote
        address user;
        // The referrer of the user filling the OB quote
        address referrer;
        // The size to fill from the OB quote (18 decimals)
        UD60x18 size;
        // secp256k1 'r', 's', and 'v' value
        Signature signature;
    }

    struct PremiumAndFeeInternal {
        UD60x18 totalReferralRebate;
        UD60x18 premium;
        UD60x18 protocolFee;
        UD60x18 premiumTaker;
        ReferralVarsInternal referral;
    }

    struct QuoteAMMVarsInternal {
        UD60x18 liquidity;
        UD60x18 maxSize;
        UD60x18 totalPremium;
        UD60x18 totalTakerFee;
    }

    struct SettlePositionVarsInternal {
        bytes32 pKeyHash;
        uint256 tokenId;
        UD60x18 size;
        UD60x18 claimableFees;
        UD60x18 payoff;
        UD60x18 collateral;
    }
}
