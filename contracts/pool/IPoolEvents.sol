// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

import {Position} from "../libraries/Position.sol";

interface IPoolEvents {
    event UpdateTick(
        UD60x18 indexed tick,
        UD60x18 indexed prev,
        UD60x18 indexed next,
        SD59x18 delta,
        UD60x18 externalFeeRate,
        SD59x18 longDelta,
        SD59x18 shortDelta,
        uint256 counter
    );

    event Deposit(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 collateral,
        UD60x18 longs,
        UD60x18 shorts,
        UD60x18 lastFeeRate,
        UD60x18 claimableFees,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick
    );

    event Withdrawal(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 collateral,
        UD60x18 longs,
        UD60x18 shorts,
        UD60x18 lastFeeRate,
        UD60x18 claimableFees,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick
    );

    event ClaimFees(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 feesClaimed,
        UD60x18 lastFeeRate
    );

    event ClaimProtocolFees(address indexed feeReceiver, UD60x18 feesClaimed);

    event FillQuoteRFQ(
        bytes32 indexed quoteRFQHash,
        address indexed user,
        address indexed provider,
        UD60x18 contractSize,
        Position.Delta deltaMaker,
        Position.Delta deltaTaker,
        UD60x18 premium,
        UD60x18 protocolFee,
        UD60x18 rebate,
        bool isBuy
    );

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 protocolFee
    );

    event Trade(
        address indexed user,
        UD60x18 contractSize,
        Position.Delta delta,
        UD60x18 premium,
        UD60x18 takerFee,
        UD60x18 protocolFee,
        UD60x18 marketPrice,
        UD60x18 liquidityRate,
        UD60x18 currentTick,
        UD60x18 rebate,
        bool isBuy
    );

    event Exercise(
        address indexed holder,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 settlementPrice,
        UD60x18 fee
    );

    event Settle(
        address indexed user,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 settlementPrice,
        UD60x18 fee
    );

    event Annihilate(address indexed owner, UD60x18 contractSize, uint256 fee);

    event SettlePosition(
        address indexed owner,
        uint256 indexed tokenId,
        UD60x18 contractSize,
        UD60x18 collateral,
        UD60x18 exerciseValue,
        UD60x18 feesClaimed,
        UD60x18 settlementPrice,
        UD60x18 fee
    );

    event TransferPosition(
        address indexed owner,
        address indexed receiver,
        uint256 srcTokenId,
        uint256 destTokenId
    );

    event CancelQuoteRFQ(address indexed provider, bytes32 quoteRFQHash);

    event FlashLoan(
        address indexed initiator,
        address indexed receiver,
        UD60x18 amount,
        UD60x18 fee
    );
}
