// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";

import {IPosition} from "../libraries/IPosition.sol";
import {IPricing} from "../libraries/IPricing.sol";
import {Position} from "../libraries/Position.sol";

import {ISignatureTransfer} from "../vendor/uniswap/ISignatureTransfer.sol";

interface IPoolInternal is IPosition, IPricing {
    error Pool__AboveQuoteSize();
    error Pool__AboveMaxSlippage();
    error Pool__ErrorNotHandled();
    error Pool__InsufficientAskLiquidity();
    error Pool__InsufficientBidLiquidity();
    error Pool__InsufficientCollateralAllowance();
    error Pool__InsufficientCollateralBalance();
    error Pool__InsufficientLiquidity();
    error Pool__InsufficientLongBalance();
    error Pool__InsufficientPermit();
    error Pool__InsufficientShortBalance();
    error Pool__InvalidAssetUpdate();
    error Pool__InvalidBelowPrice();
    error Pool__InvalidPermitRecipient();
    error Pool__InvalidPermittedToken();
    error Pool__InvalidQuoteSignature();
    error Pool__InvalidQuoteTaker();
    error Pool__InvalidRange();
    error Pool__InvalidReconciliation();
    error Pool__InvalidTransfer();
    error Pool__InvalidSwapTokenIn();
    error Pool__InvalidSwapTokenOut();
    error Pool__InvalidVersion();
    error Pool__LongOrShortMustBeZero();
    error Pool__NegativeSpotPrice();
    error Pool__NotAuthorized();
    error Pool__NotEnoughSwapOutput();
    error Pool__NotEnoughTokens();
    error Pool__OppositeSides();
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__OutOfBoundsPrice();
    error Pool__PositionDoesNotExist();
    error Pool__PositionCantHoldLongAndShort();
    error Pool__QuoteCancelled();
    error Pool__QuoteExpired();
    error Pool__QuoteOverfilled();
    error Pool__TickDeltaNotZero();
    error Pool__TickNotFound();
    error Pool__TickOutOfRange();
    error Pool__TickWidthInvalid();
    error Pool__ZeroSize();

    struct Tick {
        SD59x18 delta;
        UD60x18 externalFeeRate;
        SD59x18 longDelta;
        SD59x18 shortDelta;
        uint256 counter;
    }

    struct SwapArgs {
        // token to pass in to swap (Must be poolToken for `tradeAndSwap`)
        address tokenIn;
        // Token result from the swap (Must be poolToken for `swapAndDeposit` / `swapAndTrade`)
        address tokenOut;
        // amount of tokenIn to trade | poolToken decimals
        uint256 amountInMax;
        // min amount out to be used to purchase | poolToken decimals
        uint256 amountOutMin;
        // exchange address to call to execute the trade
        address callee;
        // address for which to set allowance for the trade
        address allowanceTarget;
        // data to execute the trade
        bytes data;
        // address to which refund excess tokens
        address refundAddress;
    }

    struct TradeQuote {
        // The provider of the quote
        address provider;
        // The taker of the quote (address(0) if quote should be usable by anyone)
        address taker;
        // The normalized option price | 18 decimals
        UD60x18 price;
        // The max size | 18 decimals
        UD60x18 size;
        // Whether provider is buying or selling
        bool isBuy;
        // Timestamp until which the quote is valid
        uint256 deadline;
        // Salt to make quote unique
        uint256 salt;
    }

    struct Delta {
        SD59x18 collateral;
        SD59x18 longs;
        SD59x18 shorts;
    }

    struct Permit2 {
        address permittedToken;
        uint256 permittedAmount;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    enum InvalidQuoteError {
        None,
        QuoteExpired,
        QuoteCancelled,
        QuoteOverfilled,
        OutOfBoundsPrice,
        InvalidQuoteTaker,
        InvalidQuoteSignature,
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
        // The number of contracts being traded | 18 decimals
        UD60x18 size;
        // Whether the taker is buying or selling
        bool isBuy;
        // Tx will revert if total premium is above this value when buying, or below this value when selling. | poolToken decimals
        uint256 premiumLimit;
        // Amount already credited before the _trade function call. In case of a `swapAndTrade` this would be the amount resulting from the swap | poolToken decimals
        uint256 creditAmount;
        // Whether to transfer collateral to user or not if collateral value is positive. Should be false if that collateral is used for a swap
        bool transferCollateralToUser;
    }

    struct TradeVarsInternal {
        UD60x18 totalTakerFees;
        UD60x18 totalProtocolFees;
        UD60x18 longDelta;
        UD60x18 shortDelta;
    }

    struct DepositArgsInternal {
        // The normalized price of nearest existing tick below lower. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
        UD60x18 belowLower;
        // The normalized price of nearest existing tick below upper. The search is done off-chain, passed as arg and validated on-chain to save gas | 18 decimals
        UD60x18 belowUpper;
        // The position size to deposit | 18 decimals
        UD60x18 size;
        // minMarketPrice Min market price, as normalized value. (If below, tx will revert) | 18 decimals
        UD60x18 minMarketPrice;
        // maxMarketPrice Max market price, as normalized value. (If above, tx will revert) | 18 decimals
        UD60x18 maxMarketPrice;
        // Collateral amount already credited before the _deposit function call. In case of a `swapAndDeposit` this would be the amount resulting from the swap | poolToken decimals
        uint256 collateralCredit;
        // The address to which refund excess credit
        address refundAddress;
    }

    struct WithdrawVarsInternal {
        uint256 tokenId;
        UD60x18 initialSize;
        UD60x18 liquidityPerTick;
        bool isFullWithdrawal;
    }

    struct Signature {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    struct FillQuoteArgsInternal {
        // The user filling the quote
        address user;
        // The size to fill from the quote | 18 decimals
        UD60x18 size;
        // secp256k1 concatenated 'r', 's', and 'v' value
        Signature signature;
    }

    struct PremiumAndFeeInternal {
        UD60x18 premium;
        UD60x18 protocolFee;
        UD60x18 premiumTaker;
        UD60x18 premiumMaker;
    }
}
