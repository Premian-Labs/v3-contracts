// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {IPoolInternal} from "./IPoolInternal.sol";

interface IPoolEvents {
    event Deposit(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 collateral,
        uint256 longs,
        uint256 shorts,
        uint256 lastFeeRate,
        uint256 claimableFees,
        uint256 marketPrice,
        uint256 liquidityRate,
        uint256 currentTick
    );

    event Withdrawal(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 collateral,
        uint256 longs,
        uint256 shorts,
        uint256 lastFeeRate,
        uint256 claimableFees,
        uint256 marketPrice,
        uint256 liquidityRate,
        uint256 currentTick
    );

    event ClaimFees(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 feesClaimed,
        uint256 lastFeeRate
    );

    event ClaimProtocolFees(address indexed feeReceiver, uint256 feesClaimed);

    event FillQuote(
        bytes32 indexed tradeQuoteHash,
        address indexed user,
        address indexed provider,
        uint256 contractSize,
        IPoolInternal.Delta deltaMaker,
        IPoolInternal.Delta deltaTaker,
        uint256 premium,
        uint256 protocolFee,
        bool isBuy
    );

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        uint256 contractSize,
        uint256 collateral,
        uint256 protocolFee
    );

    event Trade(
        address indexed user,
        uint256 contractSize,
        IPoolInternal.Delta delta,
        uint256 premium,
        uint256 takerFee,
        uint256 protocolFee,
        uint256 marketPrice,
        uint256 liquidityRate,
        uint256 currentTick,
        bool isBuy
    );

    event Exercise(
        address indexed holder,
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 spot,
        uint256 fee
    );

    event Settle(
        address indexed user,
        uint256 contractSize,
        uint256 exerciseValue,
        uint256 spot,
        uint256 fee
    );

    event Annihilate(address indexed owner, uint256 contractSize, uint256 fee);

    event SettlePosition(
        address indexed owner,
        uint256 indexed tokenId,
        uint256 contractSize,
        uint256 collateral,
        uint256 exerciseValue,
        uint256 feesClaimed,
        uint256 spot,
        uint256 fee
    );

    event TransferPosition(
        address indexed owner,
        address indexed receiver,
        uint256 srcTokenId,
        uint256 destTokenId
    );

    event CancelTradeQuote(address indexed provider, bytes32 tradeQuoteHash);
}
