// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {IERC3156FlashLender} from "@solidstate/contracts/interfaces/IERC3156FlashLender.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";

import {Position} from "../libraries/Position.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

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

    /// @notice Functionality to support the OB / OTC system.
    ///         An LP can create a OB quote for which he will do an OTC trade through
    ///         the exchange. Takers can buy from / sell to the LP then partially or
    ///         fully while having the price guaranteed.
    /// @param quoteOB The OB quote given by the provider
    /// @param size The size to fill from the OB quote (18 decimals)
    /// @param signature secp256k1 'r', 's', and 'v' value
    /// @param referrer The referrer of the user filling the OB quote
    /// @return premiumTaker The premium paid or received by the taker for the trade (poolToken decimals)
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function fillQuoteOB(
        QuoteOB calldata quoteOB,
        UD60x18 size,
        Signature calldata signature,
        address referrer
    ) external returns (uint256 premiumTaker, Position.Delta memory delta);

    /// @notice Completes a trade of `size` on `side` via the AMM using the liquidity in the Pool.
    ///         Tx will revert if total premium is above `totalPremium` when buying, or below `totalPremium` when
    ///         selling.
    /// @param size The number of contracts being traded (18 decimals)
    /// @param isBuy Whether the taker is buying or selling
    /// @param premiumLimit Tx will revert if total premium is above this value when buying, or below this value when
    ///        selling. (poolToken decimals)
    /// @param referrer The referrer of the user doing the trade
    /// @return totalPremium The premium paid or received by the taker for the trade (poolToken decimals)
    /// @return delta The net collateral / longs / shorts change for taker of the trade.
    function trade(
        UD60x18 size,
        bool isBuy,
        uint256 premiumLimit,
        address referrer
    ) external returns (uint256 totalPremium, Position.Delta memory delta);

    /// @notice Cancel given OB quotes
    /// @dev No check is done to ensure the given hash correspond to a OB quote provider by msg.sender,
    ///      but as we register the cancellation in a mapping provider -> hash, it is not possible to cancel a OB quote
    ///      created by another provider
    /// @param hashes The hashes of the OB quotes to cancel
    function cancelQuotesOB(bytes32[] calldata hashes) external;

    /// @notice Returns whether or not an OB quote is valid, given a fill size
    /// @param user The address of the user that will call the `fillQuoteOB` function to fill the OB quote
    /// @param quoteOB The OB quote to check
    /// @param size Size to fill from the OB quote (18 decimals)
    /// @param sig secp256k1 Signature
    function isQuoteOBValid(
        address user,
        QuoteOB calldata quoteOB,
        UD60x18 size,
        Signature calldata sig
    ) external view returns (bool, InvalidQuoteOBError);

    /// @notice Returns the size already filled for a given OB quote
    /// @param provider Provider of the OB quote
    /// @param quoteOBHash Hash of the OB quote
    /// @return The size already filled (18 decimals)
    function getQuoteOBFilledAmount(address provider, bytes32 quoteOBHash) external view returns (UD60x18);
}
