// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Position} from "../libraries/Position.sol";

interface IPoolInternal {
    error Pool__AboveQuoteSize();
    error Pool__CantTransferLongAndShort();
    error Pool__FullWithdrawalExpected();
    error Pool__InsufficientAskLiquidity();
    error Pool__InsufficientBidLiquidity();
    error Pool__InsufficientCollateral();
    error Pool__InsufficientContracts();
    error Pool__InsufficientFunds();
    error Pool__InsufficientWithdrawableBalance();
    error Pool__InvalidAssetUpdate();
    error Pool__InvalidBuyOrder();
    error Pool__InvalidSellOrder();
    error Pool__InvalidTransfer();
    error Pool__InvalidWithdrawal();
    error Pool__OppositeSides();
    error Pool__OptionExpired();
    error Pool__OptionNotExpired();
    error Pool__OutOfBoundsPrice();
    error Pool__PositionDoesNotExist();
    error Pool__TickInsertFailed();
    error Pool__TickInsertInvalid();
    error Pool__TickInsertInvalidLocation();
    error Pool__TickNotFound();
    error Pool__TickOutOfRange();
    error Pool__TickWidthInvalid();
    error Pool__ZeroSize();

    struct TradeQuote {
        address provider;
        uint256 price;
        uint256 size;
        Position.Side side;
    }
}
