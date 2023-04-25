// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {IPosition} from "../libraries/IPosition.sol";
import {IPricing} from "../libraries/IPricing.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolInternal is IPosition, IPricing {
    error Pool__AboveQuoteSize(UD60x18 size, UD60x18 quoteSize);
    error Pool__AboveMaxSlippage(
        uint256 value,
        uint256 minimum,
        uint256 maximum
    );
    error Pool__FlashLoanNotRepayed();
    error Pool__InsufficientAskLiquidity();
    error Pool__InsufficientBidLiquidity();
    error Pool__InsufficientLiquidity();
    error Pool__InsufficientPermit(
        uint256 requestedAmount,
        uint256 permittedAmount
    );
    error Pool__InvalidAssetUpdate(SD59x18 deltaLongs, SD59x18 deltaShorts);
    error Pool__InvalidBelowPrice(UD60x18 price, UD60x18 priceBelow);
    error Pool__InvalidPermittedToken(
        address permittedToken,
        address expectedToken
    );
    error Pool__InvalidQuoteRFQSignature();
    error Pool__InvalidQuoteRFQTaker();
    error Pool__InvalidRange(UD60x18 lower, UD60x18 upper);
    error Pool__InvalidReconciliation(uint256 crossings);
    error Pool__InvalidTransfer();
    error Pool__NotAuthorized(address sender);
    error Pool__NotEnoughTokens(UD60x18 balance, UD60x18 size);
    error Pool__NotWrappedNativeTokenPool();
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__OutOfBoundsPrice(UD60x18 price);
    error Pool__PositionDoesNotExist(address owner, uint256 tokenId);
    error Pool__PositionCantHoldLongAndShort(UD60x18 longs, UD60x18 shorts);
    error Pool__QuoteRFQCancelled();
    error Pool__QuoteRFQExpired();
    error Pool__QuoteRFQOverfilled(
        UD60x18 filledAmount,
        UD60x18 size,
        UD60x18 quoteRFQSize
    );
    error Pool__TickDeltaNotZero(SD59x18 tickDelta);
    error Pool__TickNotFound(UD60x18 price);
    error Pool__TickOutOfRange(UD60x18 price);
    error Pool__TickWidthInvalid(UD60x18 price);
    error Pool__WithdrawalDelayNotElapsed(uint256 unlockTime);
    error Pool__ZeroSize();

    struct Tick {
        SD59x18 delta;
        UD60x18 externalFeeRate;
        SD59x18 longDelta;
        SD59x18 shortDelta;
        uint256 counter;
    }

    struct QuoteRFQ {
        // The provider of the RFQ quote
        address provider;
        // The taker of the RQF quote (address(0) if RFQ quote should be usable by anyone)
        address taker;
        // The normalized option price (18 decimals)
        UD60x18 price;
        // The max size (18 decimals)
        UD60x18 size;
        // Whether provider is buying or selling
        bool isBuy;
        // Timestamp until which the RFQ quote is valid
        uint256 deadline;
        // Salt to make RFQ quote unique
        uint256 salt;
    }

    enum InvalidQuoteRFQError {
        None,
        QuoteRFQExpired,
        QuoteRFQCancelled,
        QuoteRFQOverfilled,
        OutOfBoundsPrice,
        InvalidQuoteRFQTaker,
        InvalidQuoteRFQSignature,
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
        // The number of contracts being traded (18 decimals)
        UD60x18 size;
        // Whether the taker is buying or selling
        bool isBuy;
        // Tx will revert if total premium is above this value when buying, or below this value when selling. (poolToken decimals)
        uint256 premiumLimit;
        // Whether to transfer collateral to user or not if collateral value is positive. Should be false if that collateral is used for a swap
        bool transferCollateralToUser;
    }

    struct TradeVarsInternal {
        UD60x18 totalPremium;
        UD60x18 totalTakerFees;
        UD60x18 totalProtocolFees;
        UD60x18 longDelta;
        UD60x18 shortDelta;
    }

    struct DepositArgsInternal {
        // The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
        UD60x18 belowLower;
        // The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas (18 decimals)
        UD60x18 belowUpper;
        // The position size to deposit (18 decimals)
        UD60x18 size;
        // minMarketPrice Min market price, as normalized value. (If below, tx will revert) (18 decimals)
        UD60x18 minMarketPrice;
        // maxMarketPrice Max market price, as normalized value. (If above, tx will revert) (18 decimals)
        UD60x18 maxMarketPrice;
    }

    struct WithdrawVarsInternal {
        uint256 tokenId;
        UD60x18 initialSize;
        UD60x18 liquidityPerTick;
        bool isFullWithdrawal;
        SD59x18 tickDelta;
    }

    struct Signature {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct FillQuoteRFQArgsInternal {
        // The user filling the RFQ quote
        address user;
        // The size to fill from the RFQ quote (18 decimals)
        UD60x18 size;
        // secp256k1 'r', 's', and 'v' value
        Signature signature;
        // Whether to transfer collateral to user or not if collateral value is positive. Should be false if that collateral is used for a swap
        bool transferCollateralToUser;
    }

    struct PremiumAndFeeInternal {
        UD60x18 premium;
        UD60x18 protocolFee;
        UD60x18 premiumTaker;
        UD60x18 premiumMaker;
    }
}
