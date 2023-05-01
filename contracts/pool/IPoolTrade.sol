// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IERC3156FlashLender} from "../interfaces/IERC3156FlashLender.sol";
import {IPoolInternal} from "./IPoolInternal.sol";

import {Position} from "../libraries/Position.sol";

interface IPoolTrade is IPoolInternal, IERC3156FlashLender {
    /// @notice Gives a quote for an AMM trade
    /// @param taker The taker of the trade
    /// @param size The number of contracts being traded (18 decimals)
    /// @param isBuy Whether the taker is buying or selling
    /// @return premiumNet The premium which has to be paid to complete the trade (Net of fees) (poolToken decimals)
    /// @return takerFee The taker fees to pay (Included in `premiumNet`) (poolToken decimals)
    function getQuoteAMM(
        address taker,
        UD60x18 size,
        bool isBuy
    ) external view returns (uint256 premiumNet, uint256 takerFee);

    /// @notice Functionality to support the RFQ / OTC system.
    ///         An LP can create a RFQ quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param quoteRFQ The RFQ quote given by the provider
    /// @param size The size to fill from the RFQ quote (18 decimals)
    /// @param signature secp256k1 'r', 's', and 'v' value
    /// @return premiumTaker The premium paid or received by the taker for the trade (poolToken decimals)
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function fillQuoteRFQ(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata signature
    ) external returns (uint256 premiumTaker, Position.Delta memory delta);

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    ///         Tx will revert if total premium is above `totalPremium` when buying, or below `totalPremium` when selling.
    /// @param size The number of contracts being traded (18 decimals)
    /// @param isBuy Whether the taker is buying or selling
    /// @param premiumLimit Tx will revert if total premium is above this value when buying, or below this value when selling. (poolToken decimals)
    /// @return totalPremium The premium paid or received by the taker for the trade (poolToken decimals)
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit
    ) external returns (uint256 totalPremium, Position.Delta memory delta);

    /// @notice Cancel given RFQ quotes
    /// @dev No check is done to ensure the given hash correspond to a RFQ quote provider by msg.sender,
    ///      but as we register the cancellation in a mapping provider -> hash, it is not possible to cancel a RFQ quote created by another provider
    /// @param hashes The hashes of the RFQ quotes to cancel
    function cancelQuotesRFQ(bytes32[] calldata hashes) external;

    /// @notice Returns whether or not an RFQ quote is valid, given a fill size
    /// @param quoteRFQ The RFQ quote to check
    /// @param size Size to fill from the RFQ quote (18 decimals)
    /// @param sig secp256k1 Signature
    function isQuoteRFQValid(
        QuoteRFQ calldata quoteRFQ,
        UD60x18 size,
        Signature calldata sig
    ) external view returns (bool, InvalidQuoteRFQError);

    /// @notice Returns the size already filled for a given RFQ quote
    /// @param provider Provider of the RFQ quote
    /// @param quoteRFQHash Hash of the RFQ quote
    /// @return The size already filled (18 decimals)
    function getQuoteRFQFilledAmount(
        address provider,
        bytes32 quoteRFQHash
    ) external view returns (UD60x18);
}
