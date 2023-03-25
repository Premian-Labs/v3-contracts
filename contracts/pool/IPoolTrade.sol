// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

import {Permit2} from "../libraries/Permit2.sol";
import {Position} from "../libraries/Position.sol";

interface IPoolTrade is IPoolInternal {
    /// @notice Gives a quote for a trade
    /// @param size The number of contracts being traded | 18 decimals
    /// @param isBuy Whether the taker is buying or selling
    /// @return The premium which has to be paid to complete the trade | poolToken decimals
    function getTradeQuote(
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256);

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param tradeQuote The quote given by the provider
    /// @param size The size to fill from the quote | 18 decimals
    /// @param signature  secp256k1 concatenated 'r', 's', and 'v' value
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    function fillQuote(
        TradeQuote memory tradeQuote,
        UD60x18 size,
        Signature memory signature,
        Permit2.Data memory permit
    ) external;

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    ///         Tx will revert if total premium is above `totalPremium` when buying, or below `totalPremium` when selling.
    /// @param size The number of contracts being traded | 18 decimals
    /// @param isBuy Whether the taker is buying or selling
    /// @param premiumLimit Tx will revert if total premium is above this value when buying, or below this value when selling. | poolToken decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return totalPremium The premium paid or received by the taker for the trade | poolToken decimals
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    ) external returns (uint256 totalPremium, Delta memory delta);

    /// @notice Swap tokens and completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    ///         Tx will revert if total premium is above `totalPremium` when buying, or below `totalPremium` when selling.
    /// @param s The swap arguments
    /// @param size The number of contracts being traded | 18 decimals
    /// @param isBuy Whether the taker is buying or selling
    /// @param premiumLimit Tx will revert if total premium is above this value when buying, or below this value when selling. | poolToken decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return totalPremium The premium paid or received by the taker for the trade | poolToken decimals
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    /// @return swapOutAmount The amount of pool tokens resulting from the swap | poolToken decimals
    function swapAndTrade(
        IPoolInternal.SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    )
        external
        payable
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 swapOutAmount
        );

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool, and swap the resulting collateral to another token
    ///         Tx will revert if total premium is above `totalPremium` when buying, or below `totalPremium` when selling.
    /// @param s The swap arguments
    /// @param size The number of contracts being traded | 18 decimals
    /// @param isBuy Whether the taker is buying or selling
    /// @param premiumLimit Tx will revert if total premium is above this value when buying, or below this value when selling. | poolToken decimals
    /// @param permit The permit to use for the token allowance. If no signature is passed, regular transfer through approval will be used.
    /// @return totalPremium The premium received by the taker of the trade | poolToken decimals
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    /// @return collateralReceived The amount of un-swapped collateral received from the trade. | s.tokenOut decimals
    /// @return tokenOutReceived The final amount of `s.tokenOut` received from the trade and swap. | poolToken decimals
    function tradeAndSwap(
        IPoolInternal.SwapArgs memory s,
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        Permit2.Data memory permit
    )
        external
        returns (
            uint256 totalPremium,
            Delta memory delta,
            uint256 collateralReceived,
            uint256 tokenOutReceived
        );

    /// @notice Cancel given trade quotes
    /// @dev No check is done to ensure the given hash correspond to a quote provider by msg.sender,
    ///      but as we register the cancellation in a mapping provider -> hash, it is not possible to cancel a quote created by another provider
    /// @param hashes The hashes of the quotes to cancel
    function cancelTradeQuotes(bytes32[] calldata hashes) external;

    /// @notice Returns whether or not a quote is valid, given a fill size
    /// @param tradeQuote The quote to check
    /// @param size Size to fill from the quote | 18 decimals
    /// @param sig secp256k1 Signature
    function isTradeQuoteValid(
        TradeQuote memory tradeQuote,
        UD60x18 size,
        Signature memory sig
    ) external view returns (bool, InvalidQuoteError);

    /// @notice Returns the size already filled for a given quote
    /// @param provider Provider of the quote
    /// @param tradeQuoteHash Hash of the quote
    /// @return The size already filled | 18 decimals
    function getTradeQuoteFilledAmount(
        address provider,
        bytes32 tradeQuoteHash
    ) external view returns (UD60x18);
}
