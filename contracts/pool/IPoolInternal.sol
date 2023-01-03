// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Position} from "../libraries/Position.sol";

interface IPoolInternal {
    error Pool__AboveQuoteSize();
    error Pool__InsufficientAskLiquidity();
    error Pool__InsufficientBidLiquidity();
    error Pool__InvalidAssetUpdate();
    error Pool__InvalidBelowPrice();
    error Pool__InvalidBuyOrder();
    error Pool__InvalidSellOrder();
    error Pool__InvalidTransfer();
    error Pool__LongOrShortMustBeZero();
    error Pool__OppositeSides();
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__OutOfBoundsPrice();
    error Pool__PositionDoesNotExist();
    error Pool__TickNotFound();
    error Pool__TickOutOfRange();
    error Pool__TickWidthInvalid();
    error Pool__ZeroSize();

    struct SwapArgs {
        // token to pass in to swap
        address tokenIn;
        // amount of tokenIn to trade
        uint256 amountInMax;
        //min amount out to be used to purchase
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
        address provider;
        uint256 price;
        uint256 size;
        bool isBuy;
    }
}
